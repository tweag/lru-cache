;; Least recently used cache library for Chicken Scheme
;; Copyright (C) 2026 Christopher Harrison
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
   lru-cache-capacity)

  (import scheme
          (chicken base)
          (chicken format)
          (chicken type)
          (srfi 69)
          matchable)

  ;; Doubly linked list helpers

  ; Doubly linked list node type
  (define-type dll-node (pair * pair))

  (: dll-set-previous! (dll-node * -> noreturn))
  (define (dll-set-previous! node previous-key)
    (set-car! (cdr node) previous-key))

  (: dll-set-next! (dll-node * -> noreturn))
  (define (dll-set-next! node next-key)
    (set-cdr! (cdr node) next-key))

  ;; LRU cache implementation

  ; Cache types
  ; TODO cache key type should be more liberal
  (define-type lru-cache-closure (symbol #!rest * -> *))
  (define-type cache-key (or symbol list))

  (: make-lru-cache (#!optional integer -> lru-cache-closure))
  (define (make-lru-cache #!optional (max-size 64))

    ; The cache is a hash table, that represents a doubly linked list; its
    ; keys are arbitrary (*), with values of the form:
    ;
    ;   (<payload : *> . (<previous key : *> . <next key : *>)
    ;
    ; A sentinel symbol is used to denote the termini of the list, but we
    ; also cache both the head and tail nodes for efficiency.
    (let* ((terminus (cons 'sentinel '())))
      (letrec ((head  (the cache-key terminus))
               (tail  (the cache-key terminus))
               (cache (the hash-table (make-hash-table #:size max-size)))

               ; Recursively build up the list of keys by traversing the
               ; doubly linked list from a given start
               (dll-keys (lambda (key)
                           (if (eq? key terminus)
                             ; Empty list if there are no entries
                             '()

                             (match (hash-table-ref cache key)
                               ; List end
                               (`(,_ . (,_ . ,terminus)) (list key))

                               ; Otherwise
                               (`(,_ . (,_ . ,next))
                                 (cons key (dll-keys next)))))))

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
                              (`(,_ . (,terminus . ,_)) (void))

                              ; Node is the tail
                              (`(,_ . (,previous . ,terminus))
                                ; Previous node becomes the tail
                                (dll-set-next! (hash-table-ref cache previous) terminus)
                                (set! tail previous)

                                ; Move node to head
                                (dll-set-previous! (hash-table-ref cache head) key)
                                (dll-set-previous! node terminus)
                                (dll-set-next! node head)
                                (set! head key))

                              ; Node is somewhere in the middle
                              (`(_ . (,previous . ,next))
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
                                   (`(,_ . (,terminus . ,terminus))
                                     (hash-table-delete! cache key)
                                     (set! head terminus)
                                     (set! tail terminus))

                                   ; Node is the head
                                   (`(,_ . (,terminus . ,next))
                                     (hash-table-delete! cache key)
                                     (dll-set-previous! (hash-table-ref cache next) terminus)
                                     (set! head next))

                                   ; Node is the tail
                                   (`(,_ . (,previous . ,terminus))
                                     (hash-table-delete! cache key)
                                     (dll-set-next! (hash-table-ref cache previous) terminus)
                                     (set! tail previous))

                                   ; Node is somewhere in the middle
                                   (`(,_ . (,previous . ,next))
                                     (hash-table-delete! cache key)
                                     (dll-set-next! (hash-table-ref cache previous) next)
                                     (dll-set-previous! (hash-table-ref cache next) previous))))))

               (self (lambda msg
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

                         ; List of keys in MRU-to-LRU order
                         (`(keys) (dll-keys head))

                         ; Otherwise fail
                         (_ (error "Unknown or invalid message"))))))

        self)))

  ;; TODO Public API

  (: lru-cache-size (lru-cache-closure -> integer))
  (define (lru-cache-size lru-cache) (lru-cache 'size))

  (: lru-cache-capacity (lru-cache-closure -> integer))
  (define (lru-cache-capacity lru-cache) (lru-cache 'capacity))

  )
