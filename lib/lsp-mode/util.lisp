(in-package :lem-lsp-mode)

(defun getpid ()
  #+sbcl (sb-posix:getpid)
  #+ccl (ccl::getpid)
  #+lispworks (system::getpid))

(defun wrap-text-1 (str width)
  (setq str (concatenate 'string str " "))
  (do* ((len (length str))
        (lines nil)
        (begin-curr-line 0)
        (prev-space 0 pos-space)
        (pos-space (position #\Space str)
                   (when (< (1+ prev-space) len)
                     (position #\Space str :start (1+ prev-space)))))
      ((null pos-space) (progn (push (subseq str begin-curr-line (1- len)) lines) (nreverse lines)))
    (when (> (- pos-space begin-curr-line) width)
      (push (subseq str begin-curr-line prev-space) lines)
      (setq begin-curr-line (1+ prev-space)))))

(defun wrap-text (str width)
  (format nil "~{~A~^~%~}" (wrap-text-1 str width)))

(defmacro let-hash (bindings hash-table &body body)
  (alexandria:once-only (hash-table)
    `(let ,(mapcar (lambda (b)
                     `(,b (gethash ,(string b) ,hash-table)))
                   bindings)
       ,@body)))

(defun {} (&rest plist)
  (alexandria:plist-hash-table plist :test 'equal))

(defun -> (table &rest keys)
  (loop :for k* :on keys
        :for k := (first k*)
        :do (if (rest k*)
                (progn
                  (setf table (gethash k table))
                  (unless (hash-table-p table)
                    (return nil)))
                (setf table (gethash k table)))
        :finally (return table)))

(defun merge-table (parent child)
  (maphash (lambda (key value)
             (setf (gethash key child) value))
           parent)
  child)

(defun string-to-char (string)
  (assert (and (stringp string) (= 1 (length string))))
  (char string 0))
