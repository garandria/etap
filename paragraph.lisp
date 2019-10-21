(in-package :etap)

(defclass pinned ()
  ((x :initform 0 :initarg :x :accessor x)
   (y :initform 0 :initarg :y :accessor y)))

(defclass pinned-character (pinned)
  ((character-metrics
    :initform nil :initarg :character-metrics :accessor character-metrics)))

(defun make-pinned-character (&rest initargs)
  (apply #'make-instance 'pinned-character initargs))

(defmethod width ((pinned-character pinned-character))
  (with-slots ((width tfm:width) (font tfm:font))
      (character-metrics pinned-character)
    (* (tfm:design-size font) width)))

(defmethod height ((pinned-character pinned-character))
  (with-slots ((height tfm:height) (font tfm:font))
      (character-metrics pinned-character)
    (* (tfm:design-size font) height)))

(defmethod depth ((pinned-character pinned-character))
  (with-slots ((depth tfm:depth) (font tfm:font))
      (character-metrics pinned-character)
    (* (tfm:design-size font) depth)))


(defclass line ()
  ((width :initform 0 :initarg :width :accessor width)
   (height :initform 0 :initarg :height :accessor height)
   (depth :initform 0 :initarg :depth :accessor depth)
   (pinned-characters
    :initform nil :initarg :pinned-characters :accessor pinned-characters)))

(defun make-line (&rest initargs)
  (apply #'make-instance 'line initargs))

(defmethod initialize-instance :after ((line line) &key)
  (loop :for pinned-character :in (pinned-characters line)
	:maximize (height pinned-character) :into height
	:maximize (depth pinned-character) :into depth
	:finally (setf (height line) height (depth line) depth))
  (let ((last-pinned-character (car (last (pinned-characters line)))))
    (setf (width line)
	  (+ (x last-pinned-character) (width last-pinned-character)))))


(defclass pinned-line (pinned)
  ((line :initform nil :initarg :line :accessor line)))

(defun make-pinned-line (&rest initargs)
  (apply #'make-instance 'pinned-line initargs))

(defmethod width ((pinned-line pinned-line))
  (width (line pinned-line)))

(defmethod height ((pinned-line pinned-line))
  (height (line pinned-line)))

(defmethod depth ((pinned-line pinned-line))
  (depth (line pinned-line)))


(defclass paragraph ()
  ((width :initform 0 :initarg :width :accessor width)
   (height :initform 0 :initarg :height :accessor height)
   (depth :initform 0 :initarg :depth :accessor depth)
   (pinned-lines :initform nil :initarg :pinned-lines :accessor pinned-lines)))

(defun make-paragraph (&rest initargs)
  (apply #'make-instance 'paragraph initargs))

(defmethod initialize-instance :after ((paragraph paragraph) &key disposition)
  (with-slots (width height depth pinned-lines) paragraph
    (when pinned-lines
      (case disposition
	(:flush-right
	 (dolist (pinned-line pinned-lines)
	   (setf (x pinned-line) (- width (width pinned-line)))))
	(:centered
	 (dolist (pinned-line pinned-lines)
	   (setf (x pinned-line) (/ (- width (width pinned-line)) 2)))))
      (setf height (height (first pinned-lines))
	    depth (+ (depth (car (last pinned-lines)))
		     (* (1- (length pinned-lines)) 12))))))


(defun lineup-width (lineup start end &optional (glue-length :natural))
  (setq glue-length (case glue-length
		      (:natural #'value)
		      (:max #'max-length)
		      (:min #'min-length)))
  (unless end (setq end (length lineup)))
  (loop :with width := 0
	:for i :from start :upto (1- end)
	:for element := (aref lineup i)
	:if (typep element 'tfm::character-metrics)
	  :do (incf width (* (tfm:design-size (tfm:font element))
			     (tfm:width element)))
	:else :if (kernp element)
		:do (incf width (value element))
	:else :if (gluep element)
		:do (incf width (funcall glue-length element))
	:finally (return width)))

(defun lineup-span (lineup start end)
  (unless end (setq end (length lineup)))
  (loop :with width := 0
	:with stretch := 0
	:with shrink := 0
	:for i :from start :upto (1- end)
	:for element := (aref lineup i)
	:if (typep element 'tfm::character-metrics)
	  :do (incf width (* (tfm:design-size (tfm:font element))
			     (tfm:width element)))
	:else :if (kernp element)
		:do (incf width (value element))
	:else :if (gluep element)
		:do (incf width (value element))
		:and :do (incf stretch (stretch element))
		:and :do (incf shrink (shrink element))
	:finally (return (list width (+ width stretch) (- width shrink)))))

(defun delta (lineup start end width)
  (/ (- width (lineup-width lineup start end))
     (count-if #'gluep lineup :start start :end end)))

(defun next-glue-position (lineup &optional (start 0))
  (position-if #'gluep lineup :start start))

(defgeneric line-end (start lineup width algorithm disposition)
  (:method (start lineup width algorithm disposition &aux glue-length)
    (setq glue-length (case algorithm
			((:fixed :best-fit) :natural)
			(:first-fit :max)
			(:last-fit :min)))
    (loop :for i := (next-glue-position lineup start) :then ii
	  :for ii := (when i (next-glue-position lineup (1+ i)))
	  :for w := (lineup-width lineup start i glue-length) :then (+ w ww)
	  :for ww := (when i (lineup-width lineup i ii glue-length))
	  :while (and ww (<= (+ w ww) width))
	  :finally (return i)))
  (:method (start lineup width algorithm (disposition (eql :justified)))
    (loop :with underfull-span
	  :with fit-spans := (list)
	  :with overfull-span
	  :for i := (next-glue-position lineup start) :then ii
	  :for ii := (when i (next-glue-position lineup (1+ i)))
	  :for s := (lineup-span lineup start i) :then (mapcar #'+ s ss)
	  :for ss := (when i (lineup-span lineup i ii))
	  ;; #### NOTE: s becomes NIL when doing (mapcar #'+ s NIL).
	  :while (and s (not overfull-span))
	  :if (< (cadr s) width)
	    :do (setq underfull-span (cons i s))
	  :else :if (and (<= (caddr s) width) (>= (cadr s) width))
		  :do (push (cons i s) fit-spans)
	  :else :do (setq overfull-span (cons i s))
	  :finally
	     (return (case algorithm
		       (:first-fit
			(cond (fit-spans (caar (last fit-spans)))
			      (underfull-span (car underfull-span))
			      (t (car overfull-span))))
		       (:last-fit
			(cond (fit-spans (caar fit-spans))
			      (overfull-span (car overfull-span))
			      (t (car underfull-span))))
		       (:best-fit
			(if fit-spans
			  ;; #### NOTE: two choices might be best-equals,
			  ;; when we get the same delta, once for shrink and
			  ;; once for stretch. We could offer those two
			  ;; alternatives.
			  (cdr (first (sort
				       (mapcar
					   (lambda (fit-span)
					     (cons (delta lineup start
							  (car fit-span) width)
						   (car fit-span)))
					 fit-spans)
				       #'<
				       :key (lambda (elt) (abs (car elt))))))
			  (let ((underfull-delta
				  (when underfull-span
				    (- width
				       (lineup-width
					lineup start (car underfull-span)))))
				(overfull-delta
				  (when overfull-span
				    (- (lineup-width
					lineup start (car underfull-span))
				       width))))
			    (cond ((and underfull-delta overfull-delta)
				   (if (< underfull-delta overfull-delta)
				     (car underfull-span)
				     (car overfull-span)))
				  (underfull-delta (car underfull-span))
				  (t (car overfull-span)))))))))))

(defun line-boundaries (lineup width algorithm disposition)
  (loop :for start := 0 :then (when end (1+ end))
	:while start
	:for end := (line-end start lineup width algorithm disposition)
	:collect (list start end)))

(defun create-line-1 (lineup start end glue-length)
  (unless end (setq end (length lineup)))
  (make-line
   :pinned-characters
   (loop :with x := 0
	 :for i :from start :upto (1- end)
	 :for element := (aref lineup i)
	 :if (typep element 'tfm::character-metrics)
	   :collect (make-pinned-character :x x :character-metrics element)
	   :and :do (incf x (* (tfm:width element)
			       (tfm:design-size (tfm:font element))))
	 :else :if (kernp element)
		 :do (incf x (value element))
	 :else :if (gluep element)
		 :do (incf x (funcall glue-length element)))))

(defgeneric create-line (lineup boundary width algorithm disposition)
  (:method (lineup boundary width algorithm disposition
	    &aux (start (car boundary)) (end (cadr boundary)) glue-length)
    (setq glue-length (case algorithm
			((:fixed :best-fit) #'value)
			(:first-fit #'max-length)
			(:last-fit #'min-length)))
    (create-line-1 lineup start end glue-length))
  (:method (lineup boundary width algorithm (disposition (eql :justified))
	    &aux (start (car boundary)) (end (cadr boundary)) span glue-length)
    (setq span (lineup-span lineup start end)
	  glue-length
	  (cond ((> (caddr span) width) #'min-length)
		((< (cadr span) width) #'max-length)
		(t (let ((delta (delta lineup start end width)))
		     (lambda (glue) (+ (value glue) delta))))))
    (create-line-1 lineup start end glue-length)))

(defun create-lines (lineup width algorithm disposition)
  (mapcar (lambda (boundary)
	    (create-line lineup boundary width algorithm disposition))
    (line-boundaries lineup width algorithm disposition)))

(defun create-paragraph (lineup width algorithm disposition &aux lines)
  (setf lines (when lineup (create-lines lineup width algorithm disposition)))
  (make-paragraph
   :disposition disposition
   :width width
   :pinned-lines (loop :for line :in lines
		       :for y := 0 :then (+ y 12)
		       :collect (make-pinned-line :y y :line line))))
