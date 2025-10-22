# HipJSON

A high performance implementation of JSON parser with std.json syntax. Used by Redub and Hipreme Engine.


### Testing

With `dub -c test -b release-debug --compiler=ldc2`:
```
STD JSON: 336 ms, 836 μs, and 6 hnsecs (50000 Tests)
JSONPIPE: 206 ms and 571 μs (50000 Tests)
MIR JSON: 266 ms, 770 μs, and 7 hnsecs (50000 Tests)
HipJSON: 86 ms, 881 μs, and 8 hnsecs (50000 Tests)
```

HipJSON is currently optimized with d-segmented-hashmap, which makes it get a much faster parsing speed as it never rehashes its dictionaries.
It also has a string buffer performance optimization which makes it even faster when you're dealing with mostly strings.


### Using the Javascript large object generation

Call `node genLargeObject.js` first to generate testJson.json
- JS performance of the parseJSON:
Parsed: 50.00 MB in 0.7036 s
Speed: 71.06 MB/s

- HipJSON parsing that same file
`Call with dub test -b release-debug --compiler=ldc2`

Took: 606ms
MB per Second: 86.5162
Allocated: 739.969 MB
Free: 68.7608 MB
Used: 739.962 MB
Collection Count: 7
Collection Time: 273 ms, 757 μs, and 5 hnsecs