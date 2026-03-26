;; Least recently used cache library for Chicken Scheme
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

(module lru-cache

  ;; Exports
  (make-lru-cache
   lru-cache-size
   lru-cache-capacity
   lru-cache-ref
   lru-cache-set!
   lru-cache-delete!
   lru-cache-clear!
   lru-cache-has-key?
   lru-cache-for-each
   lru-cache-fold
   lru-cache->alist
   lru-cache-keys
   lru-cache-values
   define-memoised/lru
   memoise/lru)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken type)
          (srfi 69)
          matchable)

  ;; Doubly linked list helpers

  ; Doubly linked list node type
  (define-type dll-node (pair 'v (pair 'k 'k)))

  (: dll-set-previous! (dll-node 'k -> void))
  (define (dll-set-previous! node previous-key)
    (set-car! (cdr node) previous-key))

  (: dll-set-next! (dll-node 'k -> void))
  (define (dll-set-next! node next-key)
    (set-cdr! (cdr node) next-key))

  ;; LRU cache implementation

  ; Cache type (somewhat impenetrable!)
  (define-type lru-cache-closure (symbol #!rest * -> *))

  (: make-lru-cache (#!optional integer -> lru-cache-closure))
  (define (make-lru-cache #!optional (max-size 64))

    ; The cache is a hash table, that represents a doubly linked list; its
    ; keys are arbitrary (*), with values of the form:
    ;
    ;   (<payload : *> . (<previous key : *> . <next key : *>)
    ;
    ; A sentinel symbol is used to denote the termini of the list, but we
    ; also cache both the head and tail nodes for efficiency.
    (let* ((terminus (cons 'sentinel '()))
           (terminus? (lambda (x) (eq? x terminus))))

      (letrec ((head  terminus)
               (tail  terminus)
               (cache (the hash-table (make-hash-table #:size max-size)))

               ; Does the node exist in the cache?
               (has-node? (lambda (key)
                            (hash-table-exists? cache key)))

               ; Get the node, which we assume exists, from the cache and
               ; reorder the list
               (get-node! (lambda (key)
                            (define node (hash-table-ref cache key))

                            ; Reorder the list
                            (match node
                              ; Node is already the head
                              ((_ . ((? terminus?) . _)) (void))

                              ; Node is the tail
                              ((_ . (previous . (? terminus?)))
                                ; Previous node becomes the tail
                                (dll-set-next! (hash-table-ref cache previous) terminus)
                                (set! tail previous)

                                ; Move node to head
                                (dll-set-previous! (hash-table-ref cache head) key)
                                (dll-set-previous! node terminus)
                                (dll-set-next! node head)
                                (set! head key))

                              ; Node is somewhere in the middle
                              ((_ . (previous . next))
                                ; Point previous node to next and vice versa
                                (dll-set-next! (hash-table-ref cache previous) next)
                                (dll-set-previous! (hash-table-ref cache next) previous)

                                ; Move node to head
                                (dll-set-previous! (hash-table-ref cache head) key)
                                (dll-set-previous! node terminus)
                                (dll-set-next! node head)
                                (set! head key)))

                            node))

               ; Add a node, which we assume doesn't exist in the cache,
               ; to its head
               (add-node! (lambda (key value)
                            ; Evict the tail node when at capacity
                            (when (= (hash-table-size cache) max-size)
                              (remove-node! tail))

                            (hash-table-set!
                              cache
                              key
                              `(,value . (,terminus . ,head)))

                            ; Make the old head point back to the new one
                            (unless (eq? head terminus)
                              (dll-set-previous! (hash-table-ref cache head) key))

                            ; Update the head and tail pointers
                            (set! head key)
                            (when (eq? tail terminus) (set! tail key))))

               ; Remove a node from the cache, by key
               (remove-node! (lambda (key)
                               (unless (eq? key terminus)
                                 ; Reorder the list
                                 (match (hash-table-ref cache key)
                                   ; When there's only one cached item
                                   ((_ . ((? terminus?) . (? terminus?)))
                                     (hash-table-delete! cache key)
                                     (set! head terminus)
                                     (set! tail terminus))

                                   ; Node is the head
                                   ((_ . ((? terminus?) . next))
                                     (hash-table-delete! cache key)
                                     (dll-set-previous! (hash-table-ref cache next) terminus)
                                     (set! head next))

                                   ; Node is the tail
                                   ((_ . (previous . (? terminus?)))
                                     (hash-table-delete! cache key)
                                     (dll-set-next! (hash-table-ref cache previous) terminus)
                                     (set! tail previous))

                                   ; Node is somewhere in the middle
                                   ((_ . (previous . next))
                                     (hash-table-delete! cache key)
                                     (dll-set-next! (hash-table-ref cache previous) next)
                                     (dll-set-previous! (hash-table-ref cache next) previous)))))))

               (lambda msg
                 (match msg
                   ; Size of the cache
                   (`(size) (hash-table-size cache))

                   ; Capacity of the cache
                   (`(capacity) max-size)

                   ; Get cache entry
                   (`(entry ,key)
                     (if (has-node? key)
                       (car (get-node! key))
                       (error "no such key" key)))

                   ; Get cache entry, with fallback computation
                   (`(entry ,key ,thunk)
                     (if (has-node? key)
                       (car (get-node! key))
                       (let ((value (thunk)))
                         (add-node! key value)
                         value)))

                   ; Set a cache entry
                   (`(set! ,key ,value)
                     (if (has-node? key)
                       (set-car! (get-node! key) value)
                       (add-node! key value)))

                   ; Delete a cache entry by key
                   (`(delete! ,key)
                     (if (has-node? key)
                       (remove-node! key)
                       (error "no such key" key)))

                   ; Clear the cache
                   (`(clear!)
                     (hash-table-clear! cache)
                     (set! head terminus)
                     (set! tail terminus))

                   ; Does the cache have a given key
                   (`(has-key? ,key) (has-node? key))

                   ; Apply a function to each (key, value) pair, in
                   ; MRU-to-LRU order, without updating the key order
                   (`(for-each ,proc)
                     (let loop ((key head))
                       (unless (terminus? key)
                         (let ((node (hash-table-ref cache key)))
                           (proc key (car node))
                           (match node
                             ((_ . (_ . (? terminus?))) (void))
                             ((_ . (_ . next))          (loop next)))))))

                   ; Otherwise fail
                   (_ (error "Unknown or invalid message")))))))

  ;; Public API

  (: lru-cache-size (lru-cache-closure -> integer))
  (define (lru-cache-size lru-cache) (lru-cache 'size))

  (: lru-cache-capacity (lru-cache-closure -> integer))
  (define (lru-cache-capacity lru-cache) (lru-cache 'capacity))

  (: lru-cache-ref (lru-cache-closure 'k #!rest procedure -> 'v))
  (define lru-cache-ref
    (case-lambda
      ((lru-cache key) (lru-cache 'entry key))
      ((lru-cache key thunk) (lru-cache 'entry key thunk))))

  (: lru-cache-set! (lru-cache-closure 'k 'v -> void))
  (define (lru-cache-set! lru-cache key value) (lru-cache 'set! key value))

  (: lru-cache-delete! (lru-cache-closure 'k -> void))
  (define (lru-cache-delete! lru-cache key) (lru-cache 'delete! key))

  (: lru-cache-clear! (lru-cache-closure -> void))
  (define (lru-cache-clear! lru-cache) (lru-cache 'clear!))

  (: lru-cache-has-key? (lru-cache-closure 'k -> boolean))
  (define (lru-cache-has-key? lru-cache key) (lru-cache 'has-key? key))

  (: lru-cache-for-each (lru-cache-closure ('k 'v -> *) -> void))
  (define (lru-cache-for-each lru-cache proc) (lru-cache 'for-each proc))

  (: lru-cache-fold (lru-cache-closure ('k 'v 'a -> 'a) 'a -> 'a))
  (define (lru-cache-fold lru-cache proc init)
    (let ((acc init))
      (lru-cache-for-each lru-cache
        (lambda (key value) (set! acc (proc key value acc))))

      acc))

  (: lru-cache->alist (lru-cache-closure -> (list-of (pair 'k 'v))))
  (define (lru-cache->alist lru-cache)
    (reverse (lru-cache-fold lru-cache
               (lambda (key value acc) (cons `(,key . ,value) acc))
               '())))

  (: lru-cache-keys (lru-cache-closure -> (list-of 'k)))
  (define (lru-cache-keys lru-cache)
    (map car (lru-cache->alist lru-cache)))

  (: lru-cache-values (lru-cache-closure -> (list-of 'v)))
  (define (lru-cache-values lru-cache)
    (map cdr (lru-cache->alist lru-cache)))

  (define-syntax define-memoised/lru
    (syntax-rules ()
      ; Default capacity
      ((_ (name arg ...) body ...)
       (define name
         (let ((cache (make-lru-cache)))
           (lambda (arg ...)
             (lru-cache-ref cache
                            (list arg ...)
                            (lambda () body ...))))))

      ; Explicit capacity
      ((_ capacity (name arg ...) body ...)
       (define name
         (let ((cache (make-lru-cache capacity)))
           (lambda (arg ...)
             (lru-cache-ref cache
                            (list arg ...)
                            (lambda () body ...))))))))

  (: memoise/lru (procedure #!optional integer -> procedure))
  (define (memoise/lru proc #!optional (max-size 64))
    (let ((cache (make-lru-cache max-size)))
      (lambda args
        (cache 'entry args (lambda () (apply proc args)))))))
