module hip.data.json;
import hip.util.shashmap;

/**
 *
 * Params:
 *   jsonData = The json data to read
 *   borrowStrings = If true, the string pool size is reduced to 25% of the input length, and the strings are store by reference instead of a new GC copy. This option is ignored if SIMD is unavailable
 * Returns: A completely parsed JSON. Incomplete streams are treated as error. Check for errors with `json.hasErrorOccurred` and `json.error`
 */
JSONValue parseJSON(const(char)[] jsonData, bool borrowStrings = false)
{
    JSONParseState state = JSONParseState.initialize(jsonData.length, borrowStrings);
	JSONValue output;
	if(JSONValue.parseStream(output, state, jsonData, true) == JSONValue.IncompleteStream)
		return JSONValue.errorObj("Incomplete stream when trying to parse complete JSONValue.");
	return output;
}

version(Have_intel_intrinsics)
{
	version(LDC)
	{
		// enum HasAVX2 = __traits(targetHasFeature, "avx2");
		// enum HasAVX2 = __traits(targetHasFeature, "avx2");
	}
	enum HasAVX2 = false;
	enum HasSSE2 = true;
}
else
{
	enum HasAVX2 = false;
	enum HasSSE2 = false;
}

version(UseDHashMap)
	alias JSONObject = JSONValue[string];
else
	alias JSONObject = HashMap!(string, JSONValue)*;

private JSONObject newObject()
{
	version(UseDHashMap)
		return new JSONValue[string];
	else
		return new HashMap!(string, JSONValue);
}

struct JSONArray
{
	size_t length() const { return value.length; }
	private CacheArray!(JSONValue, 2) value;

	/**
	 * Small array that holds up to N members in static memory. Whenever bigger than N,
	 * uses default D dynamic array.
	 */
	private static struct CacheArray(T, size_t N)
	{
		union {
			private T[N] staticData;
			T[] dynData;
		}
		private uint actualLength;
		private bool usingDynamic;

		this(T[] value)
		{
			this.set(value);
		}

		private void set(T[] values)
		{
			usingDynamic = values.length > N;
			actualLength = cast(uint)values.length;
			if(!usingDynamic)
				staticData.ptr[0..values.length] = values[];
			else
				dynData = values.dup;
		}
		private void append(T value)
		{
			append((&value)[0..1]);
		}
		private void append(T[] values)
		{
			import core.stdc.string;
			if(actualLength + values.length <= N)
				memcpy(staticData.ptr + actualLength, values.ptr, values.length * T.sizeof);
			else
			{
				import std.array:uninitializedArray;
				if(!usingDynamic)
				{
					T[] dynamic = uninitializedArray!(T[])(actualLength+values.length);
					memcpy(dynamic.ptr, staticData.ptr, actualLength * T.sizeof);
					dynData = dynamic;
					usingDynamic = true;
				}
				else if (dynData.length < actualLength + values.length)
				{
					size_t newSize = actualLength+values.length > actualLength*2 ? actualLength+values.length : actualLength*2;
					dynData.length = newSize;
				}
				memcpy(dynData.ptr + actualLength, values.ptr, values.length * T.sizeof);
			}
			actualLength+= values.length;
		}

		void trim()
		{
			if(usingDynamic)
				dynData.length = actualLength;
		}
		size_t length() const { return actualLength; }
		inout(T)[] getArray() inout
		{
			if(!usingDynamic)
				return staticData[0..actualLength];
			return dynData[0..actualLength];
		}
	}

	this(JSONValue[] v)
	{
		this.value = CacheArray!(JSONValue, 2)(v);
	}

	static JSONArray* append(JSONArray* self, JSONValue v)
	{
		self.value.append(v);
		return self;
	}
	auto opOpAssign(string op, T)(T value) if(op == "~")
	{
		static if(is(T == JSONValue))
			return append(&this, value);
		else
			return append(&this, JSONValue(value));
	}
	private static JSONArray* trim(JSONArray* self)
	{
		self.value.trim();
		return self;
	}

	static JSONArray* createNew()
	{
		return new JSONArray([]);
	}

	static JSONArray* createNew(JSONValue[] data)
	{
		return new JSONArray(data);
	}


	JSONValue[] getArray(){return value.getArray;}
	const(JSONValue)[] getArray() const {return value.getArray;}
}

private enum JSONState
{
	key,
	lookingAssignment,
	lookingForNext,
	value
}

enum JSONType : ubyte
{
	bool_ = 0,
	float_ = 1,
	int_ = 2, integer = int_, uinteger = int_,
	string_ = 3, string = string_,
	array = 4,
	object = 5,
	error = 6,
	null_ = 7 //0b111
}

pragma(inline, true)
bool isWhitespace(char ch)
{
	switch(ch)
	{
		case ' ', '\t', '\n', '\r': return true;
		default: return false;
	}
}

pragma(inline, true) bool isNumber(char ch){return '0' <= ch && ch <= '9';}
pragma(inline, true) bool isNumeric(char ch){return ('0' <= ch  && ch <= '9') || ch == '-' || ch == '.';}

private union JSONData
{
	double _float;
	long _int;
	bool _bool;
	immutable(char)* _string;
	JSONObject object;
	JSONArray* array;
}

struct JSONParseState
{
	// private
	static size_t minStringPoolSize = 1024;
	public
	{
		JSONValue main;
		JSONValue* current;
		JSONState state = JSONState.value;
		JSONValue lastValue;
		StringPoolList pool;
		JSONValue[] stack;
		ptrdiff_t stackLength = 0;
		size_t line = 0;
		ptrdiff_t index;
		ptrdiff_t totalParsedIndex;
		ptrdiff_t lineStartIndex;
		string lastKey;
		StringBuffer partial;
		bool borrowStrings;
	}

	private extern(C) bool function(JSONParseState* this_, const char[] data, ptrdiff_t startIndex, out ptrdiff_t newIndex, out string theString) @trusted getNextStringFn;

	static JSONParseState initialize(size_t dataLength = 0, bool borrowStrings = false) @trusted
	{
		import std.array;
		import core.cpuid;
		JSONParseState ret = void;
		ret.main.type = JSONType.null_;
		ret.current = &ret.main;
		ret.state = JSONState.value;
		ret.lastValue = ret.main;
		float poolFactor = borrowStrings ? 0.25 : 0.5;
		ret.pool = StringPoolList(dataLength <= minStringPoolSize ? minStringPoolSize : cast(size_t)(dataLength*poolFactor));
		ret.stack = uninitializedArray!(JSONValue[])(32);
		ret.stackLength = 0;
		ret.line = 0;
		ret.index = 0;
		ret.lineStartIndex = 0;
		ret.totalParsedIndex = 0;
		ret.partial = StringBuffer.get();
		ret.getNextStringFn = null;
		ret.borrowStrings = borrowStrings;

		static if(HasAVX2)
		{
			if(avx2())
				ret.getNextStringFn = cast(typeof(getNextStringFn))&(JSONParseState.getNextStringImpl!32);
		}
		static if(HasSSE2)
		{
			if(sse2() && !ret.getNextStringFn)
				ret.getNextStringFn = cast(typeof(getNextStringFn))&(JSONParseState.getNextStringImpl!16);
		}
		if(!ret.getNextStringFn)
			ret.getNextStringFn = cast(typeof(getNextStringFn))&(JSONParseState.getNextStringImpl!0);

		return ret;
	}

	void supplyData(ref const(char)[] data, bool isFullParse)
	{
		if(isFullParse)
			return;
		if(index != 0)
		{
			partial.free(index);
			totalParsedIndex+= index;
			index = 0;
		}
		data = partial.getData(data);
	}

	pragma(inline, true)
	private bool getNextString(const char[] data, ptrdiff_t startIndex, out ptrdiff_t newIndex, out string theString) @trusted
	{
		return getNextStringFn(&this, data, startIndex, newIndex, theString);
	}
	private extern(C) bool getNextStringImpl(ushort SimdOps)(const char[] data, ptrdiff_t startIndex, out ptrdiff_t newIndex, out string theString) @trusted
	{
		assert(data[startIndex] == '"', "getNextString must start with a quotation mark");
		static if(SimdOps == 32)
		{
			import inteli.avx2intrin;
			alias bytes = byte32;
			alias intrep = long4;
			alias loadUnaligned = _mm256_loadu_si256;
			alias moveMask = _mm256_movemask_epi8;
			enum byte32 quoteMask = [0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,];
			enum byte32 backslashMask = [0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,];
		}
		else static if(SimdOps == 16)
		{
			import inteli.smmintrin;
			alias bytes = byte16;
			alias intrep = int4;
			alias loadUnaligned = _mm_loadu_si128;
			alias moveMask = _mm_movemask_epi8;
			enum byte16 quoteMask = [0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,0x22,];
			enum byte16 backslashMask = [0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,0x5c,];
		}
		size_t returnLength = 0;
		ptrdiff_t i = startIndex + 1;
		char[] ret = pool.getNewString(64);
		char ch;
		static if(SimdOps > 0)
		{
			size_t copied = 0;
			ptrdiff_t startOffset = startIndex+1;
			while(i + SimdOps <= data.length)
			{
				import core.bitop;
				bytes chunk = cast(bytes)loadUnaligned(cast(bytes*)(data.ptr + i));
				int backslashCmp = moveMask(cast(intrep)(chunk == backslashMask));
				int quoteCmp = -1;
				int quoteOffset = -1;

				if(backslashCmp != 0)
				{
					quoteCmp = moveMask(cast(intrep)(chunk == quoteMask));
					int firstSlash = bsf(backslashCmp);
					if(quoteCmp != 0)
						quoteOffset = bsf(quoteCmp);
					if(quoteOffset == -1 || firstSlash < quoteOffset)
					{
						if(returnLength + SimdOps > ret.length)
							ret = pool.resizeString(ret, returnLength*2);
						returnLength+= firstSlash;
						i+= firstSlash;
						ret[copied..returnLength] = data[startOffset..i];
						for(int idx = firstSlash; idx < SimdOps; idx++)
						{
							ch = data[i];
							switch(ch)
							{
								case '"':
									ret = pool.resizeString(ret, returnLength);
									newIndex = i;
									theString = cast(string)ret;
									return true;
								case '\\':
									if(i + 1 >= data.length)
										goto fail;
									ch = escapedCharacter(data[++i]);
									idx++;
									break;
								default: break;

							}
							ret[returnLength++] = ch;
							i++;
						}
						copied = returnLength;
						startOffset = i;
						continue;
					}
				}
				else
				{
					quoteCmp = moveMask(cast(intrep)(chunk == quoteMask));
					if(quoteCmp != 0)
						quoteOffset = bsf(quoteCmp);
				}
				if(quoteOffset != -1)
				{
					i+= quoteOffset;
					returnLength+= quoteOffset;
					if(copied == 0 && borrowStrings)
					{
						ret = pool.resizeString(ret, 0);
						theString = cast(string)data[startOffset.. i];
					}
					else
					{
						ret = pool.resizeString(ret, returnLength);
						ret[copied..returnLength] = data[startOffset.. i];
						theString = cast(string)ret;
					}
					newIndex = i;
					return true;
				}
				i+= SimdOps;
				returnLength+= SimdOps;
			}
			if(returnLength > ret.length)
				ret = pool.resizeString(ret, returnLength*2);
			ret[copied..returnLength] = data[startOffset..i];
		}

		while(i < data.length)
		{
			ch = data.ptr[i];
			switch(ch)
			{
				case '"':
					ret = pool.resizeString(ret, returnLength);
					newIndex = i;
					theString = cast(string)ret;
					return true;
				case '\\':
					if(i + 1 >= data.length)
						goto fail;
					ch = escapedCharacter(data[++i]);
					break;
				default: break;

			}
			if(returnLength >= ret.length)
				ret = pool.resizeString(ret, returnLength*2);
			ret[returnLength++] = ch;
			i++;
		}
		fail:
		newIndex = startIndex;
		pool.resizeString(ret, 0);

		return false;
	}


	private bool getNextNumber(const char[] data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out JSONData theData, out JSONType type)
	{
		assert(data[currentIndex].isNumeric);
		bool hasDecimal = false;
		bool isNegative = false;
		newIndex = currentIndex;
		ptrdiff_t indexStart = currentIndex;
		if(data[indexStart] == '-')
		{
			isNegative = true;
			indexStart++;
			newIndex++;
		}

		while(newIndex < data.length)
		{
			if(!hasDecimal && data[newIndex] == '.')
			{
				hasDecimal = true;
				newIndex++;
				if(newIndex == data.length) //return false
					break;
			}
			if(!isNumber(data[newIndex]))
				break;
			newIndex++;
		}
		if(newIndex == data.length)
		{
			newIndex = currentIndex;
			return false;
		}
		if(hasDecimal)
		{
			import std.conv:to;
			theData._float = to!double(data[indexStart..newIndex]);
			theData._float = isNegative ? -theData._float : theData._float;
			type = JSONType.float_;
		}
		else
		{
			static long strToLong(const char[] str)
			{
				long result = 0;
				foreach(ch; str)
					result = result * 10 + (ch - '0');
				return result;
			}
			theData._int = strToLong(data[indexStart..newIndex]);
			theData._int = isNegative ? -theData._int : theData._int;
			type = JSONType.int_;
		}
		//Stopped on a non number. Revert 1 step.
		newIndex--;
		return newIndex < data.length;
	}
	private string getErr(string err="", string f = __FILE_FULL_PATH__, size_t l = __LINE__)
	{
		import std.conv:to;
		return "Error at line "~line.to!string~" "~err~" on index '"~(totalParsedIndex+index -lineStartIndex).to!string~"' last parsed: "~lastValue.toString~" [Internal: "~f~":"~l.to!string~"]";
	}
	pragma(inline, true) private bool getNull(const char[] data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out JSONValue value)
	{
		newIndex = currentIndex;
		if(index + 3 < data.length && data[index..index + 4] == "null")
		{
			value = JSONValue(null);
			newIndex = currentIndex + 3;
			return true;
		}
		return false;
	}
	pragma(inline, true) private bool getTrue(const char[] data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out JSONValue value)
	{
		newIndex = currentIndex;
		if(index + 3 < data.length && data[index..index + 4] == "true")
		{
			value = JSONValue(true);
			newIndex = currentIndex + 3;
			return true;
		}
		return false;
	}

	pragma(inline, true) private bool getFalse(const char[] data, ptrdiff_t currentIndex, out ptrdiff_t newIndex, out JSONValue value)
	{
		newIndex = currentIndex;
		if(index + 4 < data.length && data[index..index + 5] == "false")
		{
			value = JSONValue(false);
			newIndex = currentIndex + 3;
			return true;
		}
		return false;
	}
}


struct JSONValue
{
	JSONData data;
	static if(size_t.sizeof == uint.sizeof)
	{
		private static enum bitOffset = 29;
		private static enum lengthMask = 0x1FFFFFFF;
	}
	else
	{
		///Bit offset on where the type information is stored
		private static enum bitOffset = 61;
		///All the bits that defines where length is.
		private static enum lengthMask = 0x1FFFFFFFFFFFFFFF;
	}
	///Used only for the string.
	private size_t _length = cast(size_t)JSONType.null_ << bitOffset;

	pragma(inline, true) JSONType type(JSONType t)
	{
		_length = (_length & lengthMask) | (cast(size_t)t << bitOffset);
		return t;
	}
	pragma(inline, true) JSONType type() const
	{
		return cast(JSONType)(_length >> bitOffset);
	}

	pragma(inline, true) private void setString(string s)
	{
		_length = (s.length & lengthMask) | (cast(size_t)type << bitOffset);
		data._string = s.ptr;
	}

	pragma(inline, true) private size_t length() const
	{
		return _length & lengthMask;
	}

	static JSONValue IncompleteStream()
	{
		JSONValue ret;
		ret.type = JSONType.bool_;
		ret.data._int = 2;
		return ret;
	}



	this(T)(T value)
	{
		import std.traits;
		static if(isIntegral!T)
		{
			type = JSONType.int_;
			data._int = value;
		}
		else static if(isFloatingPoint!T)
		{
			type = JSONType.float_;
			data._float = value;
		}
		else static if(is(T == bool))
		{
			type = JSONType.bool_;
			data._bool = value;
		}
		else static if(is(T == string))
		{
			type = JSONType.string_;
			setString(value);
		}
		else static if(is(T == JSONObject))
		{
			type = JSONType.object;
			data.object = value;
		}
		else static if(is(T == JSONArray*))
		{
			type = JSONType.array;
			data.array = value;
		}
		else static if(is(T == JSONValue[]))
		{
			data.array = JSONArray.createNew(value);
			type = JSONType.array;
		}
		else static if(is(T == JSONValue))
		{
			_length = value._length;
			data = value.data;
		}
		else static if(is(T == typeof(null)))
		{
			data.object = null;
			type = JSONType.null_;
		}
		else static assert(false, "Unsupported type ", T.stringof);
	}

    int integer() const {return get!int;}
    bool boolean() const {return get!bool;}
    string str() const {return get!string;}
    string error() const{return get!string;}
    ///Returns an array range.
    auto array() const
    {
		import std.exception;
        enforce(type == JSONType.array, "Tried to iterate a non array object of type "~getTypeName);
        struct JSONValueArrayIterator
        {
            private const(JSONArray*) arr;
            private size_t idx = 0;
            size_t length(){return arr.length;}
            bool empty(){return idx == arr.length;}
            void popFront(){idx++;}
            const(JSONValue) front(){return arr.getArray()[idx];}
            const(JSONValue) opIndex(size_t num){return arr.getArray()[num];}
        }
        return JSONValueArrayIterator(data.array);
    }

	ref JSONArray jsonArray()
	{
		return *data.array;
	}

	JSONValue[] array()
	{
		import std.exception;
		enforce(type == JSONType.array, "Tried to iterate a non array object of type "~getTypeName);
		return data.array.getArray();
	}

    JSONValue object() const
    {
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		JSONValue ret;
		ret.data = data;
		ret.type = JSONType.object;
        return ret;
    }

	string[] keys()
	{
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		return data.object.keys;
	}
	JSONValue[] values()
	{
		import std.exception;
        enforce(type == JSONType.object, "Tried to get type object but value is of type "~getTypeName);
		return data.object.values;
	}

	string getTypeName() const
	{
		final switch(type) with(JSONType)
		{
			case int_: return "int";
			case bool_: return "bool";
			case float_: return "float";
			case string_: return "string";
			case object: return "object";
			case array: return "array";
			case error: return "error";
			case null_: return "null";
		}
	}

	T get(T)() const
	{
		import std.traits;
		import std.exception;
		static if(isIntegral!T)
		{
			enforce(type == JSONType.int_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._int;
		}
		else static if(isFloatingPoint!T)
		{
			enforce(type == JSONType.float_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._float;
		}
		else static if(is(T == bool))
		{
			enforce(type == JSONType.bool_, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return cast(Unqual!T)data._bool;
		}
		else static if(is(T == string))
		{
			enforce(type == JSONType.string_ || type == JSONType.error, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return data._string[0..length];
		}
		else static if(is(T == JSONObject))
		{
			enforce(type == JSONType.object, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return data.object;
		}
		else static if(is(T == JSONArray))
		{
			enforce(type == JSONType.array, "Tried to get type "~T.stringof~" but value is of type "~getTypeName);
			return *data.array;
		}
	}
	bool isNull()
	{
		with(JSONType)
		{
			if(type == null_) return true;
			if(type == JSONType.object) return data.object == null;
			if(type == JSONType.array) return data.array == null;
		}
		return false;
	}

	static JSONValue emptyObject()
	{
		JSONValue ret;
		ret.type = JSONType.object;
		ret.data.object = newObject();
		return ret;
	}
	static JSONValue emptyArray()
	{
		JSONValue ret;
		ret.type = JSONType.array;
		ret.data.array = JSONArray.createNew();
		return ret;
	}

	private static JSONValue errorObj(string message)
	{
		JSONValue ret;
		ret.setString(message);
		ret.type = JSONType.error;
		return ret;
	}

	static JSONValue parseStream(ref JSONValue output, ref JSONParseState parseState, const(char)[] data, bool isFullParse = false)
	{
		import std.conv:to;
		if(!data.length)
			return JSONValue.errorObj("No data provided");
		parseState.supplyData(data, isFullParse);
		with(parseState)
		{
			do
			{
				char ch = data[index];
				switch(ch)
				{
					case '\n': line++; lineStartIndex = index+totalParsedIndex; break;
					case ' ', '\r', '\t', '\b': break;
					case '{':
					{
						if(state != JSONState.value)
							return output = JSONValue.errorObj(getErr());
						JSONValue obj = emptyObject;
						if(!pushNewScope(obj, current, stackLength, stack, lastKey))
							return output = JSONValue.errorObj(getErr("Could not push new scope in JSON. Only array, object or null are valid"));

						state = JSONState.key;
						break;
					}
					case '}':
						// if(state != JSONState.lookingForNext)
						// 	return JSONValue.errorObj(getErr());
						popScope(stackLength, stack, current);
						state = JSONState.lookingForNext;
						break;
					case ':':
						if(state != JSONState.lookingAssignment)
							return output = JSONValue.errorObj(getErr("expected key before ':'"));
						state = JSONState.value;
						break;
					case '"':
					{

						switch(state)
						{
							case JSONState.lookingForNext:
								if(current.type == JSONType.object)
									goto case JSONState.key;
								else if(current.type == JSONType.array)
									goto case JSONState.value;
								goto default;
							case JSONState.key:
							{
								assert(current.type == JSONType.object, getErr("only object can receive a key."));
								ptrdiff_t currIndex = index;
								if(!getNextString(data, currIndex, index, lastKey))
								{
									index = currIndex;
									return IncompleteStream;
									//return JSONValue.errorObj(getErr("unclosed quotes."));
								}
								state = JSONState.lookingAssignment;
								break;
							}
							case JSONState.value:
							{
								string val;
								ptrdiff_t currIndex = index;
								if(!getNextString(data, currIndex, index, val))
								{
									index = currIndex;
									return IncompleteStream;
									//return JSONValue.errorObj(getErr("unclosed quotes."));
								}
								pushToStack(JSONValue(val), current, lastValue, lastKey);
								state = JSONState.lookingForNext;
								break;
							}
							default:
								return JSONValue.errorObj(getErr("comma expected before key "~lastKey));
						}
						break;
					}
					case '[':
					{
						if(state != JSONState.lookingForNext && state != JSONState.value)
							return output = JSONValue.errorObj(getErr(" expected to be a value. "));
						if(!pushNewScope(JSONValue(JSONArray.createNew()), current, stackLength, stack, lastKey))
							return output = JSONValue.errorObj(getErr("Could not push new scope in JSON. Only array, object or null are valid"));
						state = JSONState.value;
						break;
					}
					case ']':
						if(state != JSONState.lookingForNext && state != JSONState.value)
							return output = JSONValue.errorObj(getErr("expected to be a value. "));
						popScope(stackLength, stack, current);
						state = JSONState.lookingForNext;
						break;
					case ',':
						if(state != JSONState.lookingForNext)
							return output = JSONValue.errorObj(getErr("unexpected comma. "));
						if(current.type != JSONType.object && current.type != JSONType.array)
							return output = JSONValue.errorObj(getErr("unexpected comma. "));

						switch(current.type) with(JSONType)
						{
							case object: state = JSONState.key; break;
							case array: state = JSONState.value; break;
							default: assert(false, "Error?");
						}
						break;
					case 't':
						assert(state == JSONState.value || state == JSONState.lookingForNext); //Any value or array
						ptrdiff_t currentIndex = index;
						if(!getTrue(data, currentIndex, index, lastValue))
						{
							index = currentIndex;
							return IncompleteStream;
						}
						if(state == JSONState.lookingForNext && current.type != JSONType.array)
							return output = JSONValue.errorObj(getErr(lastValue.toString));
						pushToStack(lastValue, current, lastValue, lastKey);
						state = JSONState.lookingForNext;
						break;
					case 'f':
						assert(state == JSONState.value || state == JSONState.lookingForNext); //Any value or array
						ptrdiff_t currentIndex = index;
						if(!getFalse(data, currentIndex, index, lastValue))
						{
							index = currentIndex;
							return IncompleteStream;
						}
						if(state == JSONState.lookingForNext && current.type != JSONType.array)
							return output = JSONValue.errorObj(getErr(lastValue.toString));
						pushToStack(lastValue, current, lastValue, lastKey);
						state = JSONState.lookingForNext;
						break;
					case 'n':
						assert(state == JSONState.value || state == JSONState.lookingForNext); //Any value or array
						ptrdiff_t currentIndex = index;
						if(!getNull(data, currentIndex, index, lastValue))
						{
							index = currentIndex;
							return IncompleteStream;
						}
						if(state == JSONState.lookingForNext && current.type != JSONType.array)
							return output = JSONValue.errorObj(getErr(lastValue.toString));
						pushToStack(lastValue, current, lastValue, lastKey);
						state = JSONState.lookingForNext;
						break;
					case '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.':
						if(state == JSONState.lookingForNext && current.type != JSONType.array)
							return output = JSONValue.errorObj(getErr("unexpected number."));
						JSONType out_type;
						ptrdiff_t currentIndex = index;
						if(!getNextNumber(data, currentIndex, index, lastValue.data, out_type))
						{
							index = currentIndex;
							return IncompleteStream;
						}
						lastValue.type = out_type;
						pushToStack(lastValue, current, lastValue, lastKey);
						state = JSONState.lookingForNext;
					break;
					default:break;
				}
				index++;
			}
			while(index < data.length);
			if(stackLength == 0)
			{
				output = parseState.main;
				pool.trim();
				return parseState.main;
			}
		}
		return JSONValue.IncompleteStream();
	}

	inout(JSONValue) opIndex(string key) inout
	{
		assert(type == JSONType.object, "Can't get a member from a non object.");
		version(UseDHashMap)
			return (data.object)[key];
		else
			return (*data.object)[key];
	}
	JSONValue opIndexAssign(JSONValue v, string key)
	{
		import std.exception;
		enforce(type == JSONType.object, "Can't get a member from a non object.");
		enforce(data.object !is null, "Can't access a null object");
		version(UseDHashMap)
			(data.object)[key] = v;
		else
			(*data.object)[key] = v;
		return v;
	}

	JSONValue opIndexAssign(T)(T value, string key) if(!is(T == JSONValue))
	{
		return opIndexAssign(JSONValue(value), key);
	}

	inout(JSONValue)* opBinaryRight(string op)(string key) inout
	if(op == "in")
	{
		if(type != JSONType.object)	return null;
		version(UseDHashMap)
			return key in data.object;
		else
			return key in *data.object;
	}

    int opApply(scope int delegate(string key, JSONValue v) dg)
    {
        if(type != JSONType.object)
        {
            assert(false, "Can't iterate with key[string] and value[JSONValue] an object of type "~getTypeName);
        }
        int result = 0;
		version(UseDHashMap)
			auto obj = data.object;
		else
			auto obj = *data.object;
        foreach (k, v ; obj)
        {
            result = dg(k, v);
            if (result)
                break;
        }

        return result;
    }
	bool hasErrorOccurred() const { return type == JSONType.error; }

	/**
	 * Params:
	 *   compressed = Won't include any space in the file. Also, won't escape backslash. Since the parsing works with a single backslash.
	 * this may reduce the json size, and increase the parsing speed.
	 *   selfPrintkey = Only used for objects.
	 * Returns:
	 */
	string toString(bool compressed = false)() const
	{
		StringBufferSink sink;
		sink.initialize();
		toString(sink);
		return sink.finalize;
	}
	void toString(bool compressed = false, OutputSink)(ref OutputSink str) const
	{
		import std.format;
		final switch ( type )
		{
			case JSONType.int_:
				formattedWrite(str, "%s", data._int);
				break;
			case JSONType.float_:
				formattedWrite(str, "%f", data._float);
				break;
			case JSONType.bool_:
				if(data._int == 2) str~= "Incomplete Stream";
				else str~= data._bool ? "true" : "false";
				break;
			case JSONType.error:
				str~= error();
				break;
			case JSONType.string_:
				str~= '"';
				escapeCharacters(str, get!string);
				str~='"';
				break;
			case JSONType.null_:
				str~="null";
				break;
			case JSONType.array:
			{
				str~= '[';
				bool isFirst = true;
				foreach(v; data.array.getArray)
				{
					if(!isFirst)
					{
						static if(compressed)
							str~= ',';
						else
							str~= ", ";
					}
					isFirst = false;
					v.toString!compressed(str);
				}
				str~= ']';
				break;
			}
			case JSONType.object:
			{
				str~= '{';
				version(UseDHashMap)
					auto obj = data.object;
				else
					auto obj = *data.object;
				uint i = 0;
				foreach(k, v; obj)
				{
					if(i++)
					{
						static if(compressed)
							str~= `,"`;
						else
							str~= `, "`;
					}
					else
						str~= '"';
					escapeCharacters(str, k);
					static if(compressed)
						str~="\":";
					else
						str~="\" : ";
					v.toString!compressed(str);
				}
				str~= '}';
				break;

			}
		}
	}
    void dispose()
    {
        if(type == JSONType.object)
        {
			version(UseDHashMap)
				auto obj = data.object;
			else
				auto obj = *data.object;
            foreach(v; obj)
                v.dispose();
        }
        else if(type == JSONType.array)
        {
            foreach(v; data.array.value.getArray)
                v.dispose();
        }

    }
}

private struct StringBuffer
{
	char[4096] staticStorage;
	char[] dynamicStorage;
	size_t usedSize = 0;

	static StringBuffer get()
	{
		StringBuffer ret = void;
		ret.usedSize = 0;
		ret.dynamicStorage = (char[]).init;
		return ret;
	}

	void appendData(const(char)[] data)
	{
		size_t newSize = usedSize + data.length;
		if(dynamicStorage.length || newSize > staticStorage.length)
		{
			size_t oldDyn = dynamicStorage.length;
			if(newSize > dynamicStorage.length)
				dynamicStorage.length = newSize;
			if(oldDyn == 0)
				dynamicStorage[0..usedSize] = staticStorage[0..usedSize];
			dynamicStorage[usedSize..newSize] = data[];
		}
		else
			staticStorage[usedSize..newSize] = data[];
		usedSize = newSize;
	}
	void reset()
	{
		usedSize = 0;
	}

	void free(size_t freeSize)
	{
		import core.stdc.string;
		if(freeSize == 0)
			return;
		else if(freeSize >= usedSize)
		{
			usedSize = 0;
			return;
		}
		size_t remaining = usedSize - freeSize;
		if(dynamicStorage.length)
			memmove(dynamicStorage.ptr, dynamicStorage.ptr+freeSize, remaining);
		else
			memmove(staticStorage.ptr, staticStorage.ptr+freeSize, remaining);

		usedSize = remaining;

	}

	scope const(char)[] getData(const(char)[] data)
	{
		appendData(data);
		return getData();
	}

	scope const(char)[] getData()
	{
		if(dynamicStorage.length)
			return dynamicStorage[0..usedSize];
		return staticStorage[0..usedSize];
	}
}

private struct StringPoolList
{
	size_t defaultPoolSizes;
	StringPool firstPool;
	StringPool[] pools;
	this(size_t defaultPoolSizes)
	{
		this.defaultPoolSizes = defaultPoolSizes;
		firstPool = StringPool(defaultPoolSizes);
	}

	char[] getNewString(size_t strSize)
	{
		char[] ret = firstPool.getNewString(strSize);
		if(ret)
			return ret;

		if(pools.length)
			ret = pools[$-1].getNewString(strSize);
		if(!ret)
		{
			pools.length++;
			pools[$-1] = StringPool(strSize > defaultPoolSizes ? strSize : defaultPoolSizes);
			ret = pools[$-1].getNewString(strSize);
		}
		return ret;
	}


	char[] resizeString(char[] str, size_t newSize) @trusted
	{
		char[] ret = firstPool.resizeString(str, newSize);
		if(ret) return ret;
		if(pools.length)
		{
			ret = pools[$-1].resizeString(str, newSize);
			if(ret) return ret;
			ret = pools[$-1].getNewString(newSize);
		}
		if(!ret)
		{
			pools.length++;
			pools[$-1] = StringPool(newSize > defaultPoolSizes ? newSize : defaultPoolSizes);
			ret = pools[$-1].getNewString(newSize);
		}
		if(str.length < newSize)
			ret[0..str.length] = str[];
		else
			ret[0..newSize] = str[0..newSize];
		assert(ret.length != 0 || (newSize == 0 && ret.length == 0));
		return ret;
	}

	void trim()
	{
		firstPool.trim();
		foreach(p; pools)
			p.trim();
	}
}

private struct StringPool
{
	private char[] pool;
	private size_t used;

	this(size_t size)
	{
		import std.array;
		this.pool = uninitializedArray!(char[])(size);
	}

	private bool getSlice(size_t sliceSize, out char[] str)
	{
		if(used+sliceSize <= pool.length)
		{
			str = pool[used..used+sliceSize];
			used+= sliceSize;
			return true;
		}
		return false;
	}

	char[] resizeString(char[] str, size_t newSize) @trusted
	{
		///Inside pool
		if(newSize == str.length) return str;
		if(pool.ptr <= str.ptr && pool.ptr + pool.length > str.ptr)
		{
			if(newSize > str.length)
			{
				if(newSize - str.length + used > pool.length)
				{
					used-= str.length;
					return null;
				}
				else
				{
					used+= newSize - str.length;
					(cast(size_t*)&str)[0] = newSize;
					return str;
				}
			}
			else
			{
				used-= str.length - newSize;
				return str[0..newSize];
			}
		}
		return null;
	}
	/**
	*	If the pool is not enough, it will allocate randomly
	*/
	char[] getNewString(size_t strSize)
	{
		char[] ret;
		if(getSlice(strSize, ret))
			return ret;
		return null;
	}

	void trim()
	{
		pool.length = used;
		if(used == 0)
			pool = null;
	}
}


private struct StringBufferSink
{
	char[] data;
	size_t used;

	void initialize()
	{
		import std.array:uninitializedArray;
		data = uninitializedArray!(char[])(1024);
	}

	pragma(inline, true) size_t length() const { return used; }

	void reserve(size_t newSize)
	{
		if(used + newSize > data.length)
			data.length = cast(size_t)(data.length*1.75) + newSize;
	}
	pragma(inline, true) void fastPut(char ch){data[used++] = ch;}
	pragma(inline, true) void fastPut(string str)
	{
		data[used..used+str.length] = str;
		used+= str.length;
	}
	ref StringBufferSink opOpAssign(string op)(char value) if(op == "~")
	{
		reserve(used+1);
		data[used++] = value;
		return this;
	}
	ref StringBufferSink opOpAssign(string op)(string value) if(op == "~")
	{
		reserve(used+value.length);
		data[used..used+value.length] = value;
		used+= value.length;
		return this;
	}

	void put(char value)
	{
		reserve(used+1);
		data[used++] = value;
	}
	void put(string value)
	{
		reserve(used+value.length);
		data[used..used+value.length] = value;
		used+= value.length;
	}
	string finalize()
	{
		data.length = used;
		return cast(string)data[0..used];
	}
	string toString() const { return cast(string)data[0..used];}
}
pragma(inline, true)
bool pushNewScope(JSONValue val, ref JSONValue* current, ref ptrdiff_t stackLength, ref JSONValue[] stack, string key)
{
	assert(val.type == JSONType.object || val.type == JSONType.array || val.type == JSONType.null_, "Unexpected push.");
	JSONValue* currTemp = current;

	stackLength++;
	if(stackLength > stack.length)
		stack~= val;
	else
		stack[stackLength-1] = val;

	current = &stack[stackLength-1];


	switch(currTemp.type)
	{
		case JSONType.object:
			putInObject(currTemp.data.object, key, *current);
			break;
		case JSONType.array:
			currTemp.data.array = JSONArray.append(currTemp.data.array, *current);
			break;
		case JSONType.null_:
			currTemp.type = val.type;
			currTemp.data = val.data;
			break;
		default: return false;
	}
	return true;
}

pragma(inline, true)
private void putInObject(ref JSONObject obj, string key, ref JSONValue current)
{
	version(UseDHashMap)
		(obj)[key] = current;
	else
		(obj).putNew(key, current);
}


pragma(inline, true)
void popScope(ref ptrdiff_t stackLength, ref JSONValue[] stack, ref JSONValue* current)
{
	assert(stackLength > 0, "Unexpected pop.");

	stackLength--;
	if(stackLength > 0)
	{
		JSONValue* next = &stack[stackLength-1];
		if(current.type == JSONType.array)
			current.data.array = JSONArray.trim(current.data.array);
		current = next;
		import std.conv;
		assert(current.type == JSONType.object || current.type == JSONType.array, "Unexpected value in stack. (Typed "~(cast(size_t)(current.type)).to!string);
	}
}

pragma(inline, true)
void pushToStack(JSONValue val, ref JSONValue* current, ref JSONValue lastValue, string lastKey)
{
	switch(current.type) with(JSONType)
	{
		case object:
			putInObject(current.data.object, lastKey, val);
			break;
		case array:
			current.data.array = JSONArray.append(current.data.array, val);
			break;
		case null_:
			*current = val;
			break;
		default: assert(false, "Unexpected stack type: "~current.getTypeName);
	}
	lastValue = val;
}

pragma(inline, true)
private char escapedCharacter(char a)
{
	switch(a)
	{
		case 'n': return '\n';
		case 't': return '\t';
		case 'b': return '\b';
		case 'r': return '\r';
		default: return a;
	}
}

private void escapeCharacters(OutputSink)(ref OutputSink output, string input)
{
	import inteli.smmintrin;
	alias bytes = byte16;
	alias intrep = int4;
	alias loadUnaligned = _mm_loadu_si128;
	alias moveMask = _mm_movemask_epi8;
	enum string[6] charList = [`\"`, `\b`, `\\`, `\n`, `\r`, `\t`];
	output.reserve(output.length + input.length*2);
	size_t left = 0;


	size_t idx = 0;
	static void perByte(ref OutputSink output, string input, size_t start, size_t count = 16)
	{
		count = count + start > input.length ? input.length - start: count;
		loop: for(size_t i = start; i < start+count; i++)
		{
			switch(input[i])
			{
				static foreach(chIdx, ch; ['"', '\b', '\\', '\n', '\r', '\t'])
				{
					case ch:
						output.fastPut(charList[chIdx]);
						continue loop;
				}
				default:
					output.fastPut(input[i]);
					break;
			}
		}
	}
	while(idx < input.length)
	{
		if(idx + 16 < input.length)
		{
			bytes v = cast(bytes)loadUnaligned(cast(bytes*)(input.ptr + idx));
			auto cmp = (v == bytes('"')) |
                   	(v == bytes('\b')) |
                   	(v == bytes('\\')) |
                   	(v == bytes('\n')) |
                   	(v == bytes('\t')) |
                   	(v == bytes('\r'));
			int mask = moveMask(cast(intrep)cmp);
			if(mask == 0)
			{
				idx+= 16;
				continue;
			}
			import core.bitop;
			size_t offset = bsf(mask);
			output.fastPut(input[left..idx+offset]);
			perByte(output, input, idx+offset, 16 - offset);
			idx+= 16;
			left = idx;
		}
		else
		{
			output.fastPut(input[left..idx]);
			perByte(output, input, idx, input.length - idx);
			break;
		}
	}
}

unittest
{
	assert(parseJSON(`
{
    "name": "redub",
    "description": "Dub Based Build System, with parallelization per packages and easier to contribute",
    "authors": ["Hipreme"],
    "targetPath": "build",
    "stringImportPaths": ["source"],
    "configurations": [
        {
            "name": "cli",
            "targetType": "executable",
            "platforms": ["windows", "linux"],
            "versions": ["RedubCLI", "FSWForcePoll", "RedubWatcher"],
            "dependencies": {
                "fswatch": "~>0.6.1",
                "arsd-official:terminal": "~>12.1"
            }
        },
        {
            "name": "cli-dev",
            "versions": ["RedubCLI", "Developer", "RedubWatcher", "FSWForcePoll"],
            "targetType": "executable",
            "dependencies": {
                "fswatch": "~>0.6.1",
                "arsd-official:terminal": "~>12.1"
            }
        },
        {
            "name": "library",
            "targetType": "staticLibrary",
            "versions": ["AsLibrary"],
            "excludedSourceFiles": ["source/app.d"]
        }
    ],
    "license": "MIT",
    "dependencies": {
        "semver": {"path": "semver"},
        "colorize": {"path": "colorize"},
        "adv_diff": {"path": "adv_diff"},
        "hipjson": {"path": "C:\\Users\\Marcelo\\Documents\\D\\hipjson"},
        "d_dependencies": {"path": "d_dependencies"},
        "dub_sdl_to_json": {"path": "dub_sdl_to_json"},
        "package_suppliers": {"path": "package_suppliers"},
        "d_downloader": {"path": "d_downloader"},
        "xxhash3": "~>0.0.5"
    }
}`).object["configurations"].array.length == 3);

}

unittest
{
	enum json = `
{
    "D5F04185E96CC720": [
        [
			"First Value"
        ],
        [
			"Second Value"
        ]
    ]
}`;
	assert(parseJSON(json)["D5F04185E96CC720"].array[1].array[0].toString == `"Second Value"`);
}

unittest
{
	enum json = `
{
    "hello": "world",
	"there": "what",
	"array": [1, 2, 3, 4, 10, "Hello", true, false]
}`;
	assert(parseJSON(json).toString == `{"array" : [1, 2, 3, 4, 10, "Hello", true, false], "there" : "what", "hello" : "world"}`);
}

unittest
{
	enum json = "
{
	\"hello\": \"\nworldworldworldworld\"
}";

	assert(parseJSON(json).toString == `{"hello" : "\nworldworldworldworld"}`);
}




unittest
{
	enum path = `c:\Users\Marcelo\AppData\Local\dub\dump.json`;
	enum tests = 10;
	import core.memory;
	import std.datetime.stopwatch;
	import std.file;
	import std.stdio;

	string file = readText(path);
	// auto js = parseJSON(file, true);
	auto res = benchmark!(()
	{
		parseJSON(file, true);
		// js.toString!true();
	})(tests);

	size_t bytesRead = file.length * tests;


	writeln("Parsed: ", bytesRead / 1_000_000, " MB");
	writeln("Took: ", res[0].total!"msecs", "ms");
	writeln("MB per Second: ", bytesRead / 1_000_000.0 / (res[0].total!"msecs" / 1000.0) );

	writeln("Allocated: ", GC.stats.allocatedInCurrentThread / 1_000_000.0, " MB");
	writeln("Free: ", GC.stats.freeSize / 1_000_000.0, " MB");
	writeln("Used: ", GC.stats.usedSize / 1_000_000.0, " MB");
	writeln("Collection Count: ", GC.profileStats.numCollections);
	writeln("Collection Time: ", GC.profileStats.totalCollectionTime);
}
