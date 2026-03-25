<!-- DO NOT EDIT: generated from lru-cache.wiki by generate-readme -->

# lru-cache

## Description

An LRU (least recently used) cache for Chicken Scheme 5.

Keys and values may be of any type. The cache uses a hash table for O(1)
lookup and a doubly-linked list to maintain access ordering. When the
cache reaches capacity, the least recently used entry is evicted.

This implementation shares no lineage with the [lru-cache
egg](https://wiki.call-cc.org/eggref/4/lru-cache), for Chicken Scheme 4,
by Jim Ursetto.

## Author

Christopher Harrison ([Tweag](https://tweag.io))

## Repository

<https://github.com/tweag/lru-cache>

## Requirements

- [srfi-69](https://wiki.call-cc.org/egg/srfi-69)
- [matchable](https://wiki.call-cc.org/egg/matchable)

## API

### Cache creation

#### `(make-lru-cache [capacity])`

Create a new LRU cache. `capacity` is the maximum number of entries the
cache will hold before evicting the least recently used entry;
defaulting to 64.

### Lookup and mutation

#### `(lru-cache-ref cache key)`

Returns the value associated with `key` in `cache`, promoting it to the
most recently used position. Signals an error if `key` is not present.

#### `(lru-cache-ref cache key thunk)`

Returns the value associated with `key` in `cache` if present, promoting
it to the most recently used position. If `key` is not present, calls
`thunk` (a procedure of zero arguments) to compute the value, caches the
result and returns it.

#### `(lru-cache-set! cache key value)`

Associates `key` with `value` in `cache`. If `key` already exists,
updates its value and promotes it to the most recently used position. If
`key` is new and the cache is at capacity, the least recently used entry
is evicted.

#### `(lru-cache-delete! cache key)`

Removes the entry for `key` from `cache`. Signals an error if `key` is
not present.

#### `(lru-cache-clear! cache)`

Removes all entries from `cache`.

### Inspection

#### `(lru-cache-size cache)`

Returns the number of entries currently in `cache`.

#### `(lru-cache-capacity cache)`

Returns the maximum number of entries `cache` can hold.

#### `(lru-cache-has-key? cache key)`

Returns `#t` if `key` is present in `cache`, `#f` otherwise. Does not
affect the access ordering.

### Iteration

#### `(lru-cache-for-each cache proc)`

Apply `proc` (a procedure of two arguments: the entry key and value,
respectively) to each entry in `cache`, ordered from most recently used
to least recently used. Does not affect the access ordering.

**Note:** `proc` must not mutate `cache`.

#### `(lru-cache-fold cache proc init)`

Calls `proc` (a procedure of three arguments: the entry key, value and
accumulator, respectively) with each entry in `cache`, ordered from most
recently to least recently used; the initial folded value is `init`,
returns the final folded value. Does not affect the access ordering.

**Note:** `proc` must not mutate `cache`.

#### `(lru-cache->alist cache)`

Returns an association list of all key-value pairs in `cache`, ordered
from most recently used to least recently used. Does not affect the
access ordering.

#### `(lru-cache-keys cache)`

Returns a list of all keys in `cache`, ordered from most recently used
to least recently used. Does not affect the access ordering.

#### `(lru-cache-values cache)`

Returns a list of all values in `cache`, ordered from most recently used
to least recently used. Does not affect the access ordering.

### Memoisation

#### `(memoise/lru proc [capacity])`

Returns a new procedure that caches the results of calling `proc`.
Arguments are used as the cache key (compared as a list). `capacity`
defaults to 64.

**Note:** For recursive procedures, the memoised version must replace
the original binding for recursive calls to benefit from caching:

``` scheme
(define (fib n)
  (cond
    ((= n 0) 1)
    ((= n 1) 1)
    (else (+ (fib (- n 1)) (fib (- n 2))))))

(set! fib (memoise/lru fib))
```

## Examples

``` scheme
(import lru-cache)

;; Create a cache with capacity 3
(define cache (make-lru-cache 3))

;; Add some entries
(lru-cache-set! cache 'a 1)
(lru-cache-set! cache 'b 2)
(lru-cache-set! cache 'c 3)

(lru-cache-keys cache)    ; => (c b a)

;; Accessing an entry promotes it
(lru-cache-ref cache 'a)  ; => 1
(lru-cache-keys cache)    ; => (a c b)

;; Adding a fourth entry evicts the LRU
(lru-cache-set! cache 'd 4)
(lru-cache-keys cache)    ; => (d a c)
(lru-cache-has-key? cache 'b) ; => #f

;; Using a thunk for cache-or-compute
(lru-cache-ref cache 'e
  (lambda () (+ 40 2)))   ; => 42

;; Memoisation
(define (slow-square x)
  (begin (print "computing...") (* x x)))
(define fast-square (memoise/lru slow-square))

(fast-square 5)  ; prints "computing...", returns 25
(fast-square 5)  ; returns 25, no print
```

## License

LGPL-3.0-or-later

## Version history

0.1.0  
Initial release
