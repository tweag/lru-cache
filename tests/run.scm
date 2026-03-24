;; Tests for LRU cache library
;; Copyright (C) 2026 Tweag SARL
;;
;; This library is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; This library is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; Lesser General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public
;; License along with this library. If not, see
;; <https://www.gnu.org/licenses/>.

(import test
        (srfi 1)
        lru-cache)

(test-group "lru-cache"

  (test-group "basic ordering and reordering"
    (define cache (make-lru-cache))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (lru-cache-set! cache 'quux 789)

    (test "simple ordering" '(quux bar foo) (lru-cache-keys cache))

    (test "fetch last" 123 (lru-cache-ref cache 'foo))
    (test "order after fetch" '(foo quux bar) (lru-cache-keys cache))

    (test "fetch middle" 789 (lru-cache-ref cache 'quux))
    (test "order after fetch" '(quux foo bar) (lru-cache-keys cache))

    (test "fetch first" 789 (lru-cache-ref cache 'quux))
    (test "order after fetch" '(quux foo bar) (lru-cache-keys cache))

    (lru-cache-set! cache 'bar 999)
    (test "order after set" '(bar quux foo) (lru-cache-keys cache)))

  (test-group "eviction"
    (define cache (make-lru-cache 2))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (test "at capacity" (lru-cache-capacity cache) (lru-cache-size cache))

    (lru-cache-set! cache 'quux 789)
    (test "still at capacity" (lru-cache-capacity cache) (lru-cache-size cache))
    (test "last key evicted" '(quux bar) (lru-cache-keys cache)))

  (test-group "errors"
    (define cache (make-lru-cache))

    (test-error "fetch non-existent key" (lru-cache-ref cache 'foo))
    (test-error "delete non-existent key" (lru-cache-delete! cache 'foo)))

  (test-group "empty cache"
    (define cache (make-lru-cache))

    (test "size" 0 (lru-cache-size cache))
    (test "no such key" #f (lru-cache-has-key? cache 'foo))
    (test "keyless" '() (lru-cache-keys cache)))

  (test-group "edge case: capacity 1"
    (define cache (make-lru-cache 1))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (test "last key survives" '(bar) (lru-cache-keys cache)))

  (test-group "thunk caching"
    (define cache (make-lru-cache))

    (define counter 0)
    (define (thunk)
      (set! counter (+ counter 1))
      123)

    (lru-cache-ref cache 'foo thunk)
    (test "thunk discharged" 1 counter)

    (define fetch (lru-cache-ref cache 'foo))
    (test "thunk cached" 1 counter)
    (test "fetch" 123 fetch))

  (test-group "memoise"
    (define counter 0)
    (define (fib n)
      (set! counter (+ counter 1))
      (cond
        ((eq? n 0) 1)
        ((eq? n 1) 1)
        (else (+ (fib (- n 1)) (fib (- n 2))))))

    (set! fib (memoise/lru fib))

    (test "compute" '(1 1 2 3 5) (map fib (iota 5)))
    (test "using cached results" 5 counter))

  (test-group "delete and clear"
    (define cache (make-lru-cache))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)

    (lru-cache-delete! cache 'foo)
    (test "key deleted" '(bar) (lru-cache-keys cache))

    (lru-cache-clear! cache)
    (test "cache cleared" 0 (lru-cache-size cache))))

(test-exit)
