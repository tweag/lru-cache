;; Convert svnwiki format to HTML suitable for pandoc conversion to GFM.
;;
;; Usage: csi -s wiki2html.scm <input.wiki>
;; Outputs HTML to stdout.

(import svnwiki-sxml
        (chicken format)
        (chicken string)
        (chicken process-context)
        (chicken base))

;; Track current heading level so defs nest one level below their section
(define current-heading-level (make-parameter 0))

(define (escape-html str)
  (string-translate* str
    '(("&" . "&amp;")
      ("<" . "&lt;")
      (">" . "&gt;")
      ("\"" . "&quot;"))))

(define (emit-nodes nodes)
  (for-each emit-node nodes))

(define (emit-node node)
  (cond
    ((string? node)
     (display (escape-html node)))

    ((not (pair? node))
     (void))

    (else
     (case (car node)

       ;; Shift heading levels by -1: svnwiki == (level 2) becomes h1
       ((section)
        (let* ((level (cadr node))
               (hl (max 1 (- level 1)))
               (title (caddr node))
               (body (cdddr node)))
          (fprintf (current-output-port) "<h~a>" hl)
          (display (escape-html title))
          (fprintf (current-output-port) "</h~a>\n" hl)
          (parameterize ((current-heading-level hl))
            (emit-nodes body))))

       ;; Table of contents: omit (GitHub can generate its own)
       ((toc) (void))

       ((p)
        (display "<p>")
        (emit-nodes (cdr node))
        (display "</p>\n"))

       ;; Internal wiki links -> full Chicken wiki URLs
       ((int-link)
        (let* ((path (cadr node))
               (text (if (> (length node) 2) (caddr node) (cadr node))))
          (display "<a href=\"")
          (display (escape-html (string-append "https://wiki.call-cc.org" path)))
          (display "\">")
          (display (escape-html text))
          (display "</a>")))

       ;; External links
       ((link)
        (let* ((url (cadr node))
               (text (if (> (length node) 2) (caddr node) (cadr node))))
          (display "<a href=\"")
          (display (escape-html url))
          (display "\">")
          (display (escape-html text))
          (display "</a>")))

       ;; Procedure definition: signature as a sub-heading, then body
       ((def)
        (let ((sig (cadr node))
              (body (cddr node))
              (hl (+ 1 (current-heading-level))))
          (fprintf (current-output-port) "<h~a>" hl)
          (emit-node sig)
          (fprintf (current-output-port) "</h~a>\n" hl)
          (emit-nodes body)))

       ;; Signature container: just emit contents
       ((sig)
        (emit-nodes (cdr node)))

       ;; Procedure type in a signature
       ((procedure)
        (display "<code>")
        (display (escape-html (cadr node)))
        (display "</code>"))

       ;; Syntax type in a signature
       ((syntax)
        (display "<code>")
        (display (escape-html (cadr node)))
        (display "</code>"))

       ;; Code blocks with syntax highlighting
       ((highlight)
        (let ((lang (cadr node))
              (code (cddr node)))
          (fprintf (current-output-port) "<pre><code class=\"language-~a\">" lang)
          (for-each (lambda (c) (display (escape-html c))) code)
          (display "</code></pre>\n")))

       ;; Inline code
       ((tt)
        (display "<code>")
        (emit-nodes (cdr node))
        (display "</code>"))

       ;; Bold
       ((b)
        (display "<strong>")
        (emit-nodes (cdr node))
        (display "</strong>"))

       ;; Lists
       ((ul)
        (display "<ul>\n")
        (emit-nodes (cdr node))
        (display "</ul>\n"))

       ((li)
        (display "<li>")
        (emit-nodes (cdr node))
        (display "</li>\n"))

       ;; Definition lists (used in version history)
       ((dl)
        (display "<dl>\n")
        (emit-nodes (cdr node))
        (display "</dl>\n"))

       ((dt)
        (display "<dt>")
        (emit-nodes (cdr node))
        (display "</dt>\n"))

       ((dd)
        (display "<dd>")
        (emit-nodes (cdr node))
        (display "</dd>\n"))

       ;; Fallback: emit children
       (else
        (emit-nodes (cdr node)))))))

(define (main)
  (let* ((args (command-line-arguments))
         (filename (car args))
         (sxml (call-with-input-file filename svnwiki->sxml)))
    (emit-nodes sxml)))

(main)
