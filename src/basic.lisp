(in-package :lem)

(export '(first-line-p
          last-line-p
          bolp
          eolp
          bobp
          eobp
          beginning-of-buffer
          end-of-buffer
          beginning-of-line
          end-of-line
          goto-position
          forward-line
          shift-position
          mark-point
          following-char
          preceding-char
          char-after
          char-before
          blank-line-p
          delete-while-whitespaces
          skip-chars-forward
          skip-chars-backward
          current-column
          move-to-column
          point-to-offset
          erase-buffer

          region-beginning
          region-end
          apply-region-lines))

(defun invoke-save-excursion (function)
  (let ((point (copy-point (current-point) :temporary))
        (mark (when (buffer-mark-p (current-buffer))
                (copy-point (buffer-mark (current-buffer))
			    :temporary))))
    (unwind-protect (funcall function)
      (setf (current-buffer) (point-buffer point))
      (move-point (current-point) point)
      (when mark
        (set-current-mark mark)))))

(defun buffers-start (buffer)
  (make-point buffer 1 0 :kind :temporary))

(defun buffers-end (buffer)
  (make-point buffer
	      (buffer-nlines buffer)
	      (line-length (buffer-tail-line buffer))
	      :kind :temporary))

(defun first-line-p (point)
  (<= (point-linum point) 1))

(defun last-line-p (point)
  (<= (buffer-nlines (point-buffer point))
      (point-linum point)))

(defun start-line-p (point)
  (zerop (point-charpos point)))

(defun end-line-p (point)
  (= (point-charpos point)
     (buffer-line-length (point-buffer point)
                         (point-linum point))))

(defun start-buffer-p (point)
  (and (first-line-p point)
       (start-line-p point)))

(defun end-buffer-p (point)
  (and (last-line-p point)
       (end-line-p point)))

(defun same-line-p (point1 point2)
  (assert (eq (point-buffer point1)
              (point-buffer point2)))
  (= (point-linum point1)
     (point-linum point2)))

(defun line-start (point)
  (setf (point-charpos point) 0)
  point)

(defun line-end (point)
  (setf (point-charpos point)
        (buffer-line-length (point-buffer point)
                            (point-linum point)))
  point)

(defun buffer-start (point)
  (move-point point (buffers-start (point-buffer point))))

(defun buffer-end (point)
  (move-point point (buffers-end (point-buffer point))))

(defun move-point (point new-point)
  (let ((buffer (point-buffer point)))
    (setf (point-linum point)
          (min (point-linum new-point)
               (buffer-nlines buffer)))
    (setf (point-charpos point)
          (min (buffer-line-length buffer (point-linum point))
               (point-charpos new-point))))
  point)

(defun line-offset (point n &optional (charpos 0))
  (let ((linum (point-linum point)))
    (if (plusp n)
        (dotimes (_ n)
          (when (<= (buffer-nlines (point-buffer point)) linum)
            (return-from line-offset nil))
          (incf linum))
        (dotimes (_ (- n))
          (when (= linum 1)
            (return-from line-offset nil))
          (decf linum)))
    (setf (point-linum point) linum))
  (setf (point-charpos point)
        (if (< 0 charpos)
            (min charpos
                 (length (line-string-at point)))
            0))
  point)

(defun %character-offset-positive (point n)
  (let ((charpos (point-charpos point))
        (linum (point-linum point)))
    (loop
       (when (minusp n)
	 (setf (point-charpos point) charpos)
	 (setf (point-linum point) linum)
	 (return nil))
       (let* ((length (1+ (buffer-line-length (point-buffer point)
					      (point-linum point))))
	      (w (- length (point-charpos point))))
	 (when (< n w)
	   (incf (point-charpos point) n)
	   (return point))
	 (decf n w)
	 (unless (line-offset point 1)
	   (setf (point-charpos point) charpos)
	   (setf (point-linum point) linum)
	   (return nil))))))

(defun %character-offset-negative (point n)
  (let ((charpos (point-charpos point))
        (linum (point-linum point)))
    (loop
       (when (minusp n)
	 (setf (point-charpos point) charpos)
	 (setf (point-linum point) linum)
	 (return nil))
       (when (<= n (point-charpos point))
	 (decf (point-charpos point) n)
	 (return point))
       (decf n (1+ (point-charpos point)))
       (cond ((first-line-p point)
	      (setf (point-charpos point) charpos)
	      (setf (point-linum point) linum)
	      (return nil))
	     (t
	      (line-offset point -1)
	      (line-end point))))))

(defun character-offset (point n)
  (if (plusp n)
      (%character-offset-positive point n)
      (%character-offset-negative point (- n))))

(defun character-at (point &optional (offset 0))
  (if (zerop offset)
      (buffer-get-char (point-buffer point)
                       (point-linum point)
                       (point-charpos point))
      (with-point ((temp-point point))
        (when (character-offset temp-point offset)
          (character-at temp-point 0)))))

(defun insert-character (point char &optional (n 1))
  (loop :repeat n :do (insert-char/point point char))
  t)

(defun insert-string-at (point string &rest plist)
  (if (null plist)
      (insert-string/point point string)
      (with-point ((start-point point))
        (insert-string/point point string)
        (let ((end-point (character-offset (copy-point start-point :temporary)
                                           (length string))))
          (loop :for (k v) :on plist :by #'cddr
                :do (put-text-property start-point end-point k v)))))
  t)

(defun delete-char-at (point &optional (n 1) killp)
  (when (minusp n)
    (unless (character-offset point n)
      (return-from delete-char-at nil))
    (setf n (- n)))
  (unless (end-buffer-p point)
    (let ((string (delete-char/point point n)))
      (when killp
        (kill-push string))
      t)))

(defun erase-buffer (&optional (buffer (current-buffer)))
  (buffer-start (buffer-point buffer))
  (buffer-mark-cancel buffer)
  (delete-char/point (buffer-point buffer) t))

(defun region-beginning (&optional (buffer (current-buffer)))
  (let ((start (buffer-point buffer))
        (end (buffer-mark buffer)))
    (if (point< start end)
        start
        end)))

(defun region-end (&optional (buffer (current-buffer)))
  (let ((start (buffer-point buffer))
        (end (buffer-mark buffer)))
    (if (point< start end)
        end
        start)))

(defun apply-region-lines (start end function)
  (with-point ((start start :right-inserting)
	       (end end :right-inserting))
    (move-point (current-point) start)
    (loop :while (point< (current-point) end) :do
       (with-point ((prev (line-start (current-point))))
	 (funcall function)
	 (when (same-line-p (current-point) prev)
	   (unless (line-offset (current-point) 1)
	     (return)))))))

(defun %map-region (start end function)
  (when (point< end start)
    (rotatef start end))
  (let ((start-line (buffer-get-line (point-buffer start)
                                     (point-linum start))))
    (loop :for line := start-line :then (line-next line)
       :for linum :from (point-linum start) :to (point-linum end)
       :for firstp := (eq line start-line)
       :for lastp := (= linum (point-linum end))
       :do (funcall function
		    line
		    (if firstp
			(point-charpos start)
			0)
		    (if lastp
			(point-charpos end)
			nil))))
  (values))

(defun map-region (start end function)
  (%map-region start end
               (lambda (line start end)
                 (funcall function
                          (subseq (line-str line) start end)
                          (not (null end))))))

(defun points-to-string (start end)
  (assert (eq (point-buffer start)
              (point-buffer end)))
  (with-output-to-string (out)
    (map-region start end
                (lambda (string lastp)
                  (write-string string out)
                  (unless lastp
                    (write-char #\newline out))))))

(defun count-characters (start end)
  (let ((count 0))
    (map-region start
                end
                (lambda (string lastp)
                  (incf count (length string))
                  (unless lastp
                    (incf count))))
    count))

(defun delete-between-points (start end)
  (assert (eq (point-buffer start)
              (point-buffer end)))
  (unless (point< start end)
    (rotatef start end))
  (delete-char/point start
		     (count-characters start end)))

(defun count-lines (start end)
  (assert (eq (point-buffer start)
              (point-buffer end)))
  (when (point< end start)
    (rotatef start end))
  (with-point ((point start))
    (loop :for count :from 0 :do
       (when (point< end point)
	 (return count))
       (unless (line-offset point 1)
	 (return (1+ count))))))

(defun line-number-at-point (point)
  (count-lines (buffers-start (point-buffer point)) point))

(defun text-property-at (point key &optional (offset 0))
  (if (zerop offset)
      (line-search-property (get-line/point point) key (point-charpos point))
      (with-point ((temp-point point))
        (when (character-offset temp-point offset)
          (text-property-at temp-point key 0)))))

(defun put-text-property (start-point end-point key value)
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (%map-region start-point end-point
               (lambda (line start end)
                 (line-add-property line
                                    start
                                    (if (null end)
                                        (line-length line)
                                        end)
                                    key
                                    value
                                    (null end)))))

(defun remove-text-property (start-point end-point key)
  (assert (eq (point-buffer start-point)
              (point-buffer end-point)))
  (%map-region start-point end-point
               (lambda (line start end)
                 (line-remove-property line
                                       start
                                       (if (null end)
                                           (line-length line)
                                           end)
                                       key))))

(defun next-single-property-change (point property-name &optional limit-point)
  (let ((first-value (text-property-at point property-name))
        (start-point (copy-point point :temporary)))
    (loop
       (unless (character-offset point 1)
	 (move-point point start-point)
	 (return nil))
       (unless (eq first-value (text-property-at point property-name))
	 (return point))
       (when (and limit-point (point<= limit-point point))
	 (move-point point start-point)
	 (return nil)))))

(defun previous-single-property-change (point property-name &optional limit-point)
  (let ((first-value (text-property-at point property-name -1))
        (start-point (copy-point point :temporary)))
    (loop
       (unless (eq first-value (text-property-at point property-name -1))
	 (return point))
       (unless (character-offset point -1)
	 (move-point point start-point)
	 (return nil))
       (when (and limit-point (point>= limit-point point))
	 (move-point point start-point)
	 (return nil)))))

(defun line-string-at (point)
  (buffer-line-string (point-buffer point)
                      (point-linum point)))

(defun point-column (point)
  (string-width (line-string-at point)
                0
                (point-charpos point)))

(defun move-to-column (point column &optional force)
  (line-end point)
  (let ((cur-column (point-column point)))
    (cond ((< column cur-column)
           (setf (point-charpos point)
                 (wide-index (line-string-at point) column))
           point)
          (force
           (insert-character point #\space (- column cur-column))
           (line-end point))
          (t
           (line-end point)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defun bolp ()
  (start-line-p (current-point)))

(defun eolp ()
  (end-line-p (current-point)))

(defun bobp ()
  (start-buffer-p (current-point)))

(defun eobp ()
  (end-buffer-p (current-point)))

(defun beginning-of-buffer ()
  (buffer-start (current-point)))

(defun end-of-buffer ()
  (buffer-end (current-point)))

(defun beginning-of-line ()
  (line-start (current-point))
  t)

(defun end-of-line ()
  (line-end (current-point))
  t)

(defun goto-position (position)
  (check-type position (integer 1 *))
  (beginning-of-buffer)
  (shift-position position))

(defun forward-line (&optional (n 1))
  (line-offset (current-point) n))

(defun shift-position (n)
  (character-offset (current-point) n))

(defun check-marked ()
  (unless (buffer-mark-p (current-buffer))
    (editor-error "Not mark in this buffer")))

(defun set-current-mark (point)
  (let ((buffer (point-buffer point)))
    (cond ((buffer-mark-p buffer)
           (move-point (buffer-mark buffer)
                       point))
          (t
           (setf (buffer-mark-p buffer) t)
           (setf (buffer-mark buffer)
                 (copy-point point :right-inserting)))))
  point)

(defun following-char ()
  (character-at (current-point)))

(defun preceding-char ()
  (character-at (current-point) -1))

(defun char-after (&optional (point (current-point)))
  (character-at point 0))

(defun char-before (&optional (point (current-point)))
  (character-at point -1))

(defun delete-while-whitespaces (&optional ignore-newline-p use-kill-ring)
  (let ((n (skip-chars-forward (current-point)
                               (if ignore-newline-p
                                   '(#\space #\tab)
                                   '(#\space #\tab #\newline)))))
    (delete-char-at (current-point) (- n) use-kill-ring)))

(defun blank-line-p (point)
  (let ((string (line-string-at point))
        (eof-p (last-line-p point))
        (count 0))
    (loop :for c :across string :do
       (unless (or (char= c #\space)
		   (char= c #\tab))
	 (return-from blank-line-p nil))
       (incf count))
    (if eof-p
        count
        (1+ count))))

(defun skip-chars-internal (point test not-p dir)
  (loop :for count :from 0
     :for c := (character-at point (if dir 0 -1))
     :do
     (unless (if (if (consp test)
		     (member c test)
		     (funcall test c))
		 (not not-p)
		 not-p)
       (return count))
     (unless (character-offset point (if dir 1 -1))
       (return count))))

(defun skip-chars-forward (point test &optional not-p)
  (skip-chars-internal point test not-p t))

(defun skip-chars-backward (point test &optional not-p)
  (skip-chars-internal point test not-p nil))

(defun current-column ()
  (point-column (current-point)))

(defun point-to-offset (point)
  (let ((end-linum (point-linum point))
        (end-charpos (point-charpos point))
        (buffer (point-buffer point))
        (offset 0))
    (loop :repeat (1- end-linum)
       :for linum :from 1
       :do (incf offset
		 (1+ (buffer-line-length buffer linum))))
    (+ offset end-charpos)))
