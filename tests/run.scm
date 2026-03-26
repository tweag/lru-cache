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

    (test "keys are ordered most- to least-recently inserted"
          '(quux bar foo) (lru-cache-keys cache))

    (test "ref returns the value for an existing key"
          123 (lru-cache-ref cache 'foo))

    (test "ref promotes the least-recent key to most-recent"
          '(foo quux bar) (lru-cache-keys cache))

    (test "ref on a middle key returns its value"
          789 (lru-cache-ref cache 'quux))

    (test "ref promotes a middle key to most-recent"
          '(quux foo bar) (lru-cache-keys cache))

    (test "ref on the most-recent key returns its value"
          789 (lru-cache-ref cache 'quux))

    (test "ref on the most-recent key does not change ordering"
          '(quux foo bar) (lru-cache-keys cache))

    (lru-cache-set! cache 'bar 999)
    (test "set! on an existing key promotes it to most-recent"
          '(bar quux foo) (lru-cache-keys cache)))

  (test-group "eviction"
    (define cache (make-lru-cache 2))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (test "size equals capacity when full"
          (lru-cache-capacity cache) (lru-cache-size cache))

    (lru-cache-set! cache 'quux 789)
    (test "size does not exceed capacity after another insert"
          (lru-cache-capacity cache) (lru-cache-size cache))

    (test "least-recently used key is evicted when capacity is exceeded"
          '(quux bar) (lru-cache-keys cache)))

  (test-group "errors"
    (define cache (make-lru-cache))

    (test-error "ref raises an error for a non-existent key"
               (lru-cache-ref cache 'foo))

    (test-error "delete! raises an error for a non-existent key"
               (lru-cache-delete! cache 'foo)))

  (test-group "empty cache"
    (define cache (make-lru-cache))

    (test "size is zero for a fresh cache"
          0 (lru-cache-size cache))

    (test "has-key? returns #f for any key in an empty cache"
          #f (lru-cache-has-key? cache 'foo))

    (test "keys returns an empty list for an empty cache"
          '() (lru-cache-keys cache)))

  (test-group "edge case: capacity 1"
    (define cache (make-lru-cache 1))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (test "only the most-recently inserted key survives with capacity 1"
          '(bar) (lru-cache-keys cache)))

  (test-group "thunk caching"
    (define cache (make-lru-cache))

    (define counter 0)
    (define (thunk)
      (set! counter (+ counter 1))
      123)

    (lru-cache-ref cache 'foo thunk)
    (test "ref with thunk evaluates the thunk on a cache miss"
          1 counter)

    (define fetch (lru-cache-ref cache 'foo))
    (test "ref with thunk does not re-evaluate on a cache hit"
          1 counter)

    (test "ref returns the cached value produced by the thunk"
          123 fetch))

  (test-group "for-each"
    (define cache (make-lru-cache))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)
    (lru-cache-set! cache 'quux 789)

    (define result '())
    (lru-cache-for-each cache
      (lambda (key value) (set! result (cons `(,key . ,value) result))))

    (let ((expected '((foo . 123) (bar . 456) (quux . 789))))
      (test "visits all entries" expected result))

    (test "maintains insertion order" '(quux bar foo) (lru-cache-keys cache)))

  (test-group "alist conversion"
    (define cache (make-lru-cache))

    (lru-cache-set! cache 'foo 1)
    (lru-cache-set! cache 'bar 2)

    (test "alist" '((bar . 2) (foo . 1)) (lru-cache->alist cache)))

  (test-group "memoise (default capacity)"
    (define counter 0)
    (define-memoised/lru (fib n)
      (set! counter (+ counter 1))
      (cond
        ((= n 0) 1)
        ((= n 1) 1)
        (else (+ (fib (- n 1)) (fib (- n 2))))))

    (test "memoised function returns correct results"
          '(1 1 2 3 5) (map fib (iota 5)))

    (test "memoised function reuses cached results instead of recomputing"
          5 counter))

  (test-group "memoise (defined capacity)"
    (define counter 0)
    (define-memoised/lru 2 (fib n)
      (set! counter (+ counter 1))
      (cond
        ((= n 0) 1)
        ((= n 1) 1)
        (else (+ (fib (- n 1)) (fib (- n 2))))))

    (test "memoised function returns correct results"
          '(1 1 2 3 5) (map fib (iota 5)))

    ; The smaller capacity means more cache misses
    ; NOTE Evaluation order is not guaranteed, so this _may_ be flaky.
    (test "memoised function reuses cached results instead of recomputing"
          8 counter))

  (test-group "delete and clear"
    (define cache (make-lru-cache))

    (lru-cache-set! cache 'foo 123)
    (lru-cache-set! cache 'bar 456)

    (lru-cache-delete! cache 'foo)
    (test "delete! removes the specified key from the cache"
          '(bar) (lru-cache-keys cache))

    (lru-cache-clear! cache)
    (test "clear! removes all entries from the cache"
          0 (lru-cache-size cache))))

(test-exit)
