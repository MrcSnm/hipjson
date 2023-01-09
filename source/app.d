import std.stdio;
enum jsonSource = q{
{
	"unicode": "こんいちは",
    "こんにちは": "using unicode key",
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
        "data": [1, 2, 3, 4, 5, 6],
    },
    "testObj": {
        "simpleObj": {
            "path": "sound.wav",
            "data": [1, 2, 3, 4, 5, 6],
        },
        "anotherObj": {
            "key": "balanced"
        }
    }
	
}};


enum Tests = 10_000;

void main()
{
	import std.datetime.stopwatch;

	StopWatch timeHip = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
        import hip.data.json;
		auto json = JSONValue.parse(
			jsonSource
		);
	}
	writeln("Hip Simple JSON: ", timeHip.peek, " (",Tests, " Tests) ");

	StopWatch timeStd = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import std.json;
		parseJSON(jsonSource);
	}
	// writeln("test" in json);
	writeln("STD JSON: ", timeStd.peek, " (",Tests, " Tests) ");

	StopWatch timeMir = StopWatch(AutoStart.yes);
	foreach(_; 0..Tests)
	{
		import mir.algebraic_alias.json;
		import mir.deser.json;
		deserializeJson!JsonAlgebraic(jsonSource);
	}
	// writeln("test" in json);
	writeln("MIR JSON: ", timeMir.peek, " (",Tests, " Tests) ");

	StopWatch timeJsonPipe = StopWatch(AutoStart.yes);
    foreach(_; 0..Tests)
    {
        import iopipe.json.serialize;
        import iopipe.json.dom;
        auto j = jsonSource.deserialize!(JSONValue!string);
    }
    writeln("JSONPIPE: ", timeJsonPipe.peek, " (",Tests," Tests)");
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
