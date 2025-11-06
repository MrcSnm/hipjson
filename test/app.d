import std.stdio;
enum jsonSource = q{
{
	"こんにちは": "こんにちは",
	"preBuildCommands":["echo \"ERROR: Don't use 'dub test' to test mysql-native. Use 'run-tests' instead.\"","echo Bailing...","mkdir"],
	"description": "Dub Based Build System, with parallelization per packages and easier to contribute",
    "authors": "Hipreme",
    "hello": "oii",
    "test": "teste",
    "com,ma": "val,ue",
    "integer": -5345,
    "floating": -54.23,
    "array": [1,2],
    "strArr":  ["hello", "friend"],
    "mixedArr":  ["hello", 523, -53.23],
    "arrInArr": ["hello", [1, -2, -52.23], "again"],
    "emptyObj": {

    },
    "simpleObj": {
        "path": "sound.wav",
        "data": [1, 2, 3, 4, 5, 6]
    },
    "testObj": {
        "simpleObj": {
            "path": "sound.wav",
            "data": [1, 2, 3, 4, 5, 6]
        },
        "anotherObj": {
            "key": "balanced"
        }
    }
}};


enum Tests = 50_000;

void main()
{
	import std.datetime.stopwatch;

	import hip.data.json;
	import std.exception;
	JSONValue myJson;
	JSONParseState state = JSONParseState.initialize(0);
	enforce(JSONValue.parseStream(myJson, state, `{`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `"`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `h`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `e`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `l`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `l`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `o`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `"`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `:`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, ` `) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `"`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `w`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `o`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `r`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `l`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `d`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `"`) == JSONValue.IncompleteStream);
	enforce(JSONValue.parseStream(myJson, state, `}`) != JSONValue.IncompleteStream);
	import std.stdio;
	writeln(myJson);


	StopWatch timeStd = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import std.json;
		parseJSON(jsonSource);
	}
	// writeln("test" in json);
	writeln("STD JSON: ", timeStd.peek, " (",Tests, " Tests) ");

	StopWatch timeJsonPipe = StopWatch(AutoStart.yes);
    foreach(_; 0..Tests)
    {
        import iopipe.json.serialize;
        import iopipe.json.dom;
        auto j = jsonSource.deserialize!(JSONValue!string);
    }
    writeln("JSONPIPE: ", timeJsonPipe.peek, " (",Tests," Tests)");

	StopWatch timeMir = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import mir.algebraic_alias.json;
		import mir.deser.json;
		deserializeJson!JsonAlgebraic(jsonSource);
	}
	// writeln("test" in json);
	writeln("Mir Ion Algebraic: ", timeMir.peek, " (",Tests, " Tests) ");

	StopWatch timeMirIon = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import mir.ion.conv;
		import mir.ion.stream;
		foreach(symbolTable, scope ionValue; jsonSource.json2ion.IonValueStream)
		{
			// symbolTable is a memory efficient map of keys. See Amazon Ion for details.
		}
	}
	// writeln("test" in json);
	writeln("Mir Ion Amazon   : ", timeMirIon.peek, " (",Tests, " Tests) ");

	StopWatch timeMirAsdf = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import asdf: parseJson;
		auto json = parseJson(jsonSource);
	}
	// writeln("test" in json);
	writeln("Mir     ASDF     : ", timeMirAsdf.peek, " (",Tests, " Tests) ");

	StopWatch timeHip = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
        import hip.data.json;
		auto json = parseJSON(
			jsonSource, true
		);
	}
	writeln("HipJSON: ", timeHip.peek, " (",Tests, " Tests) ");
}

unittest
{
	auto json = JSONValue.parse(
		jsonSource
	);
	assert(json["test"].get!string == "teste");
	assert(json["com,ma"].get!string == "val,ue");
	assert(json["integer"].get!int == -5345);
	assert(json["floating"].get!float == -54.23f);
	writeln(json["array"]);
	writeln(json["strArr"]);
	writeln(json["mixedArr"]);
	writeln(json["arrInArr"]);
	writeln(json["emptyObj"]);
	writeln(json["simpleObj"]);
	writeln(json["unicode"]);
	writeln(json["testObj"]);
	writeln(json["こんにちは"]);
}
