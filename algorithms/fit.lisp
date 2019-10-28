(in-package :etap)

(defgeneric fit-line-boundary (start lineup width disposition variant
			       &key &allow-other-keys)
  (:method (start lineup width disposition variant &key)
    (let ((lineup-width-function (case variant
				   (:first #'lineup-max-width)
				   (:best #'lineup-width)
				   (:last #'lineup-min-width))))
      ;; #### NOTE: this works even the first time because at worst,
      ;; NEXT-SEARCH is gonna be (length lineup) first, and NIL only
      ;; afterwards.
      (loop :with previous-boundary
	    :for (end next-start next-search)
	      := (next-break-position lineup start)
		:then (next-break-position lineup next-search)
	    :for w := (funcall lineup-width-function lineup start end)
	    :while (and next-search (<= w width))
	    :do (setq previous-boundary (list end next-start next-search))
	    :finally (return previous-boundary))))
  (:method (start lineup width (disposition (eql :justified)) variant
	    &key prefer-shrink)
    (loop :with underfull-boundary
	  :with fit-boundaries := (list)
	  :with overfull-boundary
	  ;; #### NOTE: this works even the first time because at worst,
	  ;; NEXT-SEARCH is gonna be (length lineup) first, and NIL only
	  ;; afterwards.
	  :for boundary := (next-break-position lineup start)
	    :then (next-break-position lineup (caddr boundary))
	  :for span := (multiple-value-bind (width stretch shrink)
			   (lineup-width lineup start (car boundary))
			 (list width (+ width stretch) (- width shrink)))
	  :while (and (caddr boundary) (not overfull-boundary))
	  :if (< (cadr span) width)
	    :do (setq underfull-boundary boundary)
	  :else :if (and (<= (caddr span) width) (>= (cadr span) width))
	    :do (push boundary fit-boundaries)
	  :else
	    :do (setq overfull-boundary boundary)
	  :finally
	     (return
	       (case variant
		 (:first
		  (cond (fit-boundaries (car (last fit-boundaries)))
			(underfull-boundary underfull-boundary)
			(t overfull-boundary)))
		 (:last
		  (cond (fit-boundaries (car fit-boundaries))
			(overfull-boundary overfull-boundary)
			(t underfull-boundary)))
		 (:best
		  (if fit-boundaries
		    (if (= (length fit-boundaries) 1)
		      (car fit-boundaries)
		      (let ((sorted-scales
			      (sort
			       (mapcar
				   (lambda (boundary)
				     (cons boundary
					   (multiple-value-list
					    (lineup-scale lineup
							  start
							  (car boundary)
							  width))))
				 fit-boundaries)
			       #'<
			       :key #'caddr)))
			(if (= (caddr (first sorted-scales))
			       (caddr (second sorted-scales)))
			  (if prefer-shrink
			    (car (first sorted-scales))
			    (car (second sorted-scales)))
			  (car (first sorted-scales)))))
		    (let ((underfull-delta
			    (when underfull-boundary
			      (- width
				 (lineup-width
				  lineup start (car underfull-boundary)))))
			  (overfull-delta
			    (when overfull-boundary
			      (- (lineup-width
				  lineup start (car overfull-boundary))
				 width))))
		      (cond ((and underfull-delta overfull-delta)
			     (if (< underfull-delta overfull-delta)
			       underfull-boundary
			       overfull-boundary))
			    (underfull-delta underfull-boundary)
			    (t overfull-boundary))))))))))

(defgeneric fit-create-line
    (lineup start end search width disposition variant &key &allow-other-keys)
  (:method (lineup start end search width disposition (variant (eql :first))
	    &key relax &aux (ratio 1))
    (if relax
      (setq ratio
	    (if (< end (length lineup))
	      (let ((next-end (car (next-break-position lineup search))))
		(multiple-value-bind (type ratio)
		    (lineup-scale lineup start next-end width)
		  (if (eq type :stretch)
		    ratio
		    0)))
	      0)))
    (create-line lineup start end :stretch ratio))
  (:method
      (lineup start end search width disposition (variant (eql :best)) &key)
    (create-line lineup start end))
  (:method (lineup start end search width disposition (variant (eql :last))
	    &key relax &aux (ratio 1))
    (if relax
      (setq ratio
	    (multiple-value-bind (type ratio)
		(lineup-scale lineup start end width)
	      (if (eq type :stretch)
		0
		ratio))))
    (create-line lineup start end :shrink ratio))
  (:method (lineup start end search width (disposition (eql :justified)) variant
	    &key sloppy)
    (multiple-value-bind (type ratio) (lineup-scale lineup start end width)
      (if type
	(create-line lineup start end type (if sloppy ratio (min ratio 1)))
	(create-line lineup start end)))))

(defmethod create-lines
    (lineup width disposition (algorithm (eql :fit))
     &key variant relax sloppy prefer-shrink)
  (loop :for start := 0 :then next-start
	:until (= start (length lineup))
	:for (end next-start next-search)
	  := (fit-line-boundary start lineup width disposition variant
	       :prefer-shrink prefer-shrink)
	:collect (fit-create-line lineup start end next-search width
		     disposition variant
		   :relax relax :sloppy sloppy)))
