(in-package :etap)


(defstruct (node (:constructor make-node (boundary children)))
  boundary children)

(defun create-node (lineup boundary width hash &optional preventive-fulls)
  (when boundary
    (or (gethash (stop boundary) hash)
	(setf (gethash (stop boundary) hash)
	      (if (= (stop boundary) (length lineup))
		(make-node boundary nil)
		(multiple-value-bind
		      (underfull-boundary fit-boundaries overfull-boundary)
		    (next-boundaries lineup (next-start boundary) width)
		  (when (or preventive-fulls (not fit-boundaries))
		    (when underfull-boundary
		      (push underfull-boundary fit-boundaries))
		    (when overfull-boundary
		      (push overfull-boundary fit-boundaries)))
		  (make-node
		   boundary
		   (mapcar (lambda (boundary)
			     (create-node lineup boundary width hash))
		     fit-boundaries))))))))

(defun root-node (lineup width &optional preventive-fulls)
  (multiple-value-bind (underfull-boundary fit-boundaries overfull-boundary)
      (next-boundaries lineup 0 width)
    (when (or preventive-fulls (not fit-boundaries))
      (when underfull-boundary (push underfull-boundary fit-boundaries))
      (when overfull-boundary (push overfull-boundary fit-boundaries)))
    (let ((hash (make-hash-table)))
      (make-node
       nil
       (mapcar (lambda (boundary)
		 (create-node lineup boundary width hash preventive-fulls))
	 fit-boundaries)))))


(defun node-lines (node)
  (mapcan (lambda (child)
	    (let ((head-line (cons (next-start (node-boundary node))
				   (stop (node-boundary child))))
		  (next-lines (node-lines child)))
	      (if next-lines
		(mapcar (lambda (lines) (cons head-line lines))
		  next-lines)
		(list (list head-line)))))
    (node-children node)))

(defun root-node-lines (node)
  (mapcan (lambda (child)
	    (let ((head-line (cons 0 (stop (node-boundary child))))
		  (next-lines (node-lines child)))
	      (if next-lines
		(mapcar (lambda (lines) (cons head-line lines))
		  next-lines)
		(list (list head-line)))))
    (node-children node)))


(defstruct (solution
	    (:constructor make-solution (lines hyphens underfulls overfulls)))
  lines hyphens underfulls overfulls)

(defun create-solution (lineup width lines)
  (loop :with hyphens := 0
	:with underfulls := 0
	:with overfulls := 0
	:for line :in lines
	:unless (word-stop-p lineup (cdr line))
	  :do (incf hyphens)
	;; #### WARNING: dirty trick to not count the last line as underfull!
	:when (and (< (cdr line) (length lineup))
		   (< (lineup-max-width lineup (car line) (cdr line)) width))
	  :do (incf underfulls)
	:when (> (lineup-min-width lineup (car line) (cdr line)) width)
	  :do (incf overfulls)
	:finally
	   (return
	     (make-solution lines hyphens underfulls overfulls))))

;; #### NOTE: with the defaults (default text, 284pt, all features), there are
;; #### 66576 paragraph solutions including going through under and overfull
;; #### lines (21096 without hyphenation). The raw tree of all such solutions
;; #### has 150860 nodes (48338 without hyphenation). However, once a line
;; #### stop has been decided, all possible solutions for the next lines
;; #### remain the same, however we reached that possible stop. This means
;; #### that there is a lot of room for re-using branches. And indeed, when
;; #### sharing nodes, we fall from 150860 to 98 (from 48338 to 83 without
;; #### hyphenation).

;; #### If we avoid preventive fulls, that is, if we include only under- and
;; #### overfull solutions when there is not fit, the number of paragraph
;; #### solutions falls to 37 (it actually raises up to 61 without
;; #### hyphenation, all mistfits). The raw tree of all such solutions has
;; #### only 109 nodes (192 without hyphenations). Once shared, the actual
;; #### number of nodes falls down to 30 (33 without hyphenation).
(defun report-solutions
    (state
     &key (width (paragraph-width state))
	  (text (text state))
	  (kerning (cadr (member :kerning (features state))))
	  (ligatures (cadr (member :ligatures (features state))))
	  (hyphenation (cadr (member :hyphenation (features state))))
	  preventive-fulls)
  (let* ((lineup
	   (lineup text (font state) (hyphenation-rules state)
	     :kerning kerning :ligatures ligatures :hyphenation hyphenation))
	 (solutions
	   (mapcar (lambda (lines) (create-solution lineup width lines))
	     (root-node-lines (root-node lineup width preventive-fulls))))
	 (length 0)
	 (fits 0)
	 (fits-hyphened (make-hash-table))
	 (misfits 0))
    (loop :for solution :in solutions
	  :do (incf length)
	  :if (and (zerop (solution-hyphens solution))
		   (zerop (solution-underfulls solution))
		   (zerop (solution-overfulls solution)))
	    :do (incf fits)
	  :else :if (and (zerop (solution-underfulls solution))
			 (zerop (solution-overfulls solution)))
	    :do (if (gethash (solution-hyphens solution) fits-hyphened)
		  (setf (gethash (solution-hyphens solution) fits-hyphened)
			(1+ (gethash (solution-hyphens solution)
				     fits-hyphened)))
		  (setf (gethash (solution-hyphens solution) fits-hyphened) 1))
	  :else
	    :do (incf misfits))
    (format t "~A solutions in total.~%
~A fit solutions without hyphens.~%"
      length fits)
    (maphash (lambda (key value)
	       (format t "~A fit solutions with ~A hyphen~:P.~%"
		 value key))
	     fits-hyphened)
    (format t "~A mistfit solutions.~%" misfits)))