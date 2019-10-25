(in-package :etap)

(defgeneric fit-line-end (start lineup width disposition variant
			  &key &allow-other-keys)
  (:method (start lineup width disposition variant &key)
    (let ((lineup-width-function (case variant
				   (:first #'lineup-max-width)
				   (:best #'lineup-width)
				   (:last #'lineup-min-width))))
      (loop :for i := (next-glue-position lineup start) :then ii
	    :for ii := (when i (next-glue-position lineup (1+ i)))
	    :for w := (funcall lineup-width-function lineup start i)
	      :then (+ w ww)
	    :for ww := (when i (funcall lineup-width-function lineup i ii))
	    :while (and ww (<= (+ w ww) width))
	    :finally (return i))))
  (:method (start lineup width (disposition (eql :justified)) variant
	    &key prefer-shrink)
    (loop :with underfull-i
	  :with |fit-i's| := (list)
	  :with overfull-i
	  :for i := (next-glue-position lineup start) :then ii
	  :for ii := (when i (next-glue-position lineup (1+ i)))
	  :for s := (multiple-value-bind (width stretch shrink)
			(lineup-width lineup start i)
		      (list width (+ width stretch) (- width shrink)))
	    :then (mapcar #'+ s ss)
	  :for ss := (when i
		       (multiple-value-bind (width stretch shrink)
			   (lineup-width lineup i ii)
			 (list width (+ width stretch) (- width shrink))))
	  ;; #### NOTE: s becomes NIL when doing (mapcar #'+ s NIL).
	  :while (and s (not overfull-i))
	  :if (< (cadr s) width)
	    :do (setq underfull-i i)
	  :else :if (and (<= (caddr s) width) (>= (cadr s) width))
		  :do (push i |fit-i's|)
	  :else :do (setq overfull-i i)
	  :finally
	     (return
	       (case variant
		 (:first
		  (cond (|fit-i's| (car (last |fit-i's|)))
			(underfull-i underfull-i)
			(t overfull-i)))
		 (:last
		  (cond (|fit-i's| (car |fit-i's|))
			(overfull-i overfull-i)
			(t underfull-i)))
		 (:best
		  (if |fit-i's|
		    (if (= (length |fit-i's|) 1)
		      (car |fit-i's|)
		      (let ((sorted-scales
			      (sort
			       (mapcar
				   (lambda (i)
				     (cons i (multiple-value-list
					      (lineup-scale lineup start i
							    width))))
				 |fit-i's|)
			       #'<
			       :key (lambda (elt) (caddr elt)))))
			(if (= (caddr (first sorted-scales))
			       (caddr (second sorted-scales)))
			  (if prefer-shrink
			    (car (first sorted-scales))
			    (car (second sorted-scales)))
			  (car (first sorted-scales)))))
		    (let ((underfull-delta
			    (when underfull-i
			      (- width
				 (lineup-width lineup start underfull-i))))
			  (overfull-delta
			    (when overfull-i
			      (- (lineup-width lineup start overfull-i)
				 width))))
		      (cond ((and underfull-delta overfull-delta)
			     (if (< underfull-delta overfull-delta)
			       underfull-i
			       overfull-i))
			    (underfull-delta underfull-i)
			    (t overfull-i))))))))))

(defgeneric fit-create-line
    (lineup start end width disposition variant &key &allow-other-keys)
  (:method (lineup start end width disposition (variant (eql :first))
	    &key relax &aux (ratio 1))
    (if relax
      (setq ratio
	    (if end
	      (let ((i (next-glue-position lineup (1+ end))))
		(multiple-value-bind (type ratio)
		    (lineup-scale lineup start i width)
		  (if (eq type :stretch)
		    ratio
		    0)))
	      0)))
    (create-line lineup start end :stretch ratio))
  (:method (lineup start end width disposition (variant (eql :best)) &key)
    (create-line lineup start end))
  (:method (lineup start end width disposition (variant (eql :last))
	    &key relax &aux (ratio 1))
    (if relax
      (setq ratio
	    (multiple-value-bind (type ratio)
		(lineup-scale lineup start end width)
	      (if (eq type :stretch)
		0
		ratio))))
    (create-line lineup start end :shrink ratio))
  (:method (lineup start end width (disposition (eql :justified)) variant
	    &key sloppy)
    (multiple-value-bind (type ratio) (lineup-scale lineup start end width)
      (if type
	(create-line lineup start end type (if sloppy ratio (min ratio 1)))
	(create-line lineup start end)))))

(defmethod create-lines
    (lineup width disposition (algorithm (eql :fit))
     &key variant relax sloppy prefer-shrink)
  (loop :for start := 0 :then (when end (1+ end)) ; discard glue
	:while start
	:for end := (fit-line-end start lineup width disposition variant
		      :prefer-shrink prefer-shrink)
	:collect (fit-create-line lineup start end width disposition variant
		   :relax relax :sloppy sloppy)))
