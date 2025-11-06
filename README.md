# HipJSON

A high performance implementation of JSON parser with std.json syntax. Used by Redub and Hipreme Engine.

## Usage

```d
///Parsing
void main()
{

    import hip.data.json;
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

    JSONValue v = parseJSON(jsonSource, true); //Since v1.0.5, you can optionally pass a true argument for borrowing the strings, so they aren't allocated in the GC.
}

///Mutating and creating the DOM

void main()
{
    JSONValue m = JSONValue.emptyObject;
    m["someKey"] = JSONValue(500);
    m["here"] = 500;
    import std.stdio;
    writeln = m.toString;
}
```

## Streaming API

HipJSON also supports parsing JSON in stream. A following example:
```d
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
```

Of course this is only an example of how it works. It is best suited to be used together with a fetch API.
Also, setting a good initial size for the internal string pool makes the JSON parser way faster. It's default is to use 75% of the mentioned data size to use it. So if you can query the size before parsing the stream, it is a big win as the data won't be fragmented and intermediary allocations won't happen:

```d
JSONValue myJson;
JSONParseState state = JSONParseState.initialize(querySize("someapi.com/a/json")); // or std.file.getSize
char[4096] buffer;
while(fetch("someapi.com/a/json", buffer)) //or file.byChunk
{
    if(JSONValue.parseStream(myJson, state, buffer) != JSONValue.IncompleteStream)
        break;
}
//Your json has finished parsing
```


### Testing

With `dub -c test -b release-debug --compiler=ldc2`:

#### Target = <TODO>
```
STD JSON: 330 ms, 592 μs, and 1 hnsec (50000 Tests)
JSONPIPE: 209 ms, 604 μs, and 3 hnsecs (50000 Tests)
Mir Ion Algebraic: 259 ms, 756 μs, and 1 hnsec (50000 Tests)
Mir Ion Amazon   : <TODO>
Mir ASDF         : <TODO>
HipJSON: 78 ms, 604 μs, and 5 hnsecs (50000 Tests)
```

#### Target = Apple M4
```
STD JSON: 340 ms, 500 μs, and 7 hnsecs (50000 Tests) 
JSONPIPE: 239 ms and 89 μs (50000 Tests)
Mir Ion Algebraic: 234 ms, 974 μs, and 3 hnsecs (50000 Tests) 
Mir Ion Amazon   : 98 ms, 492 μs, and 8 hnsecs (50000 Tests) 
Mir ASDF         : 22 ms, 389 μs, and 9 hnsecs (50000 Tests) 
HipJSON: 85 ms, 877 μs, and 9 hnsecs (50000 Tests) 
```

HipJSON is currently optimized with d-segmented-hashmap, which makes it get a much faster parsing speed as it never rehashes its dictionaries.
It also has a string buffer performance optimization which makes it even faster when you're dealing with mostly strings.


## JSONs with large strings objects and strings (dub registry dump)

When it is mostly strings, HipJSON is able to reach in my PC up to 860 MB per second.
```
Parsed: 1528 MB
Took: 1779ms
MB per Second: 859.013
Allocated: 2969.01 MB
Free: 740.691 MB
Used: 1218.01 MB
Collection Count: 9
Collection Time: 287 ms, 386 ╬╝s, and 6 hnsecs
```


### Using the Javascript large object generation

Call `node genLargeObject.js` first to generate testJson.json
- JS performance of the parseJSON:
Parsed: 50.00 MB in 0.7036 s
Speed: 71.06 MB/s

- HipJSON parsing that same file
`Call with dub test -b release-debug --compiler=ldc2`

```
Took: 606ms
MB per Second: 86.5162
Allocated: 739.969 MB
Free: 68.7608 MB
Used: 739.962 MB
Collection Count: 7
Collection Time: 273 ms, 757 μs, and 5 hnsecs
```

### SIMD results for string only json

For the target JSON generated with:
```d
import std.stdio;
void main()
{
    import std.file;
    string data="{";
    string str = "https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.example.org/https://www.exampl";
    foreach(i; 0..1000_000)
    {
        import std.conv:to;
        if(i != 0)
            data~=",\n";
        data~= "\"hello"~i.to!string~"\": \""~str~"\"";
    }
    data~= "}";

    std.file.write("hello.json", data);
}
```
I got up to 1.8GBps

```
Parsed: 2768 MB
Took: 1460ms
MB per Second: 1896.5
Allocated: 3716.91 MB
Free: 145.827 MB
Used: 1308.89 MB
Collection Count: 5
Collection Time: 61 ms, 846 μs, and 7 hnsecs
1 modules passed unittests
```

And that results I got by copying the strings inside the maps. I've done some basic tests and it gone up to 3GBps if borrowing memory was allowed.