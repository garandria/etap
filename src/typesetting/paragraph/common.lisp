(in-package :etap)


;; For the interface.

(defparameter *dispositions*
  '(:flush-left :centered :flush-right :justified))

(defparameter *disposition-options* '((:overstretch t) (:overshrink t)))

(defparameter *disposition-options-help-keys*
  '(:disposition-option-overstretch :disposition-option-overshrink))

(defparameter *disposition-options-tooltips*
  '(:disposition-option-overstretch
    "In Justified disposition, stretch as needed,
ignoring the algorithm's decision."
    :disposition-option-overshrink
    "In Justified disposition, shrink as needed,
ignoring the algorithm's decision."))

(defun disposition-type (disposition)
  "Return DISPOSITION type."
  (car-or-symbol disposition))

(defun disposition-options (disposition)
  "Return DISPOSITION options."
  (cdr-or-nil disposition))



;; ==============
;; Pinned Objects
;; ==============

(defclass pinned-character (pinned)
  ((character-metrics :documentation "The pinned character."
		      :initarg :character-metrics
		      :reader character-metrics))
  (:documentation "The PINNED-CHARACTER class."))

(defun pinned-character-p (object)
  "Return T if OBJECT is a pinned character."
  (typep object 'pinned-character))

(defmethod width ((character pinned-character))
  "Return pinned CHARACTER's width."
  (width (character-metrics character)))

(defmethod height ((character pinned-character))
  "Return pinned CHARACTER's height."
  (height (character-metrics character)))

(defmethod depth ((character pinned-character))
  "Return pinned CHARACTER's depth."
  (depth (character-metrics character)))

(defun pin-character (character board x &optional (y 0))
  "Pin CHARACTER on BOARD at position (X, Y)."
  (make-instance 'pinned-character
    :character-metrics character :board board :x x :y y))


;; Always pinned, so no "pinned" prefix.
(defclass hyphenation-clue (pinned)
  ((explicitp :documentation
	      "Whether this hyphenation clue comes from an explicit hyphen."
	      :initform t :initarg
	      :explicit :reader explicitp))
  (:documentation "The HYPHENATION-CLUE class.
Hyphenation clues are positioned at Y = 0."))

(defun hyphenation-clue-p (object)
  "Return T if OBJECT is a hyphenation clue."
  (typep object 'hyphenation-clue))

(defun make-hyphenation-clue (board x &optional (explicit t))
  "Pin possibly EXPLICIT hyphenation clue at (X, 0)."
  (make-instance 'hyphenation-clue :board board :x x :explicit explicit))


;; Always pinned, so no "pinned" prefix.
(defclass bed (pinned)
  ((width :documentation "The river bed's width"
	  :initarg :width :reader width))
  (:documentation "The river BED class.
River beds stand in the middle of glue space and are positioned at Y = 0."))

(defun bedp (object)
  "Return T if OBJECT is a river bed."
  (typep object 'bed))

(defun make-bed (board x width)
  "Make a river bed of WIDTH centered at X."
  (make-instance 'bed :board board :x x :width width))



;; =====
;; Lines
;; =====

(defclass line ()
  ((lineup :documentation "The corresponding lineup."
	   :initarg :lineup
	   :reader lineup)
   (start-idx :documentation "This line's start index in LINEUP."
	      :initarg :start-idx
	      :reader start-idx)
   (stop-idx :documentation "This line's stop index in LINEUP."
	     :initarg :stop-idx
	     :reader stop-idx)
   (scale :documentation "The line'scale, as computed by the algorithm.
It may be different from the effective scale used to pin the objects,
depending on the algorithm itself, and on the Overstretch and Overshrink
disposition options)."
	  :initform 0
	  :initarg :scale
	  :reader scale)
   (effective-scale
    :documentation "The line's effective scale, used for pinning the objects.
It may be different from the scale computed by the algorithm in use, depending
on the algorithm itself, and on the Overstretch and Overshrink disposition
options)."
    :initarg :effective-scale
    :reader effective-scale)
   (pinned-objects :documentation "The list of pinned objects."
		   :reader pinned-objects))
  (:documentation "The LINE class.
A line contains a list of pinned objects (currently, characters and
hyphenation clues). The objects are positioned relatively to the line's
origin. A line also remembers its scale factor."))

(defmethod hyphenated ((line line))
  "Return LINE's hyphenation status."
  (hyphenated (aref (lineup line) (1- (stop-idx line)))))

(defmethod penalty
    ((line line) &aux (element (aref (lineup line) (1- (stop-idx line)))))
  "Return LINE's penalty."
  (if (break-point-p element) (penalty element) 0))

(defmethod width ((line line) &aux (object (car (last (pinned-objects line)))))
  "Return LINE's width."
  (+ (x object) (width object)))

(defmethod height ((line line))
  "Return LINE's height."
  (loop :for object :in (pinned-objects line) :maximize (height object)))

(defmethod depth ((line line))
  "Return LINE's depth."
  (loop :for object :in (pinned-objects line) :maximize (depth object)))

(defun flatten-lineup (lineup start stop)
  "Return a flattened list of LINEUP elements between START and STOP."
  (loop :for i :from start :upto (1- stop)
	:for elt := (lineup-aref lineup i start stop)
	:if (consp elt) :append elt :else :collect elt))

(defmethod initialize-instance :after ((line line) &key beds &aux scale)
  "Possibly initialize the LINE's effective scale, and pin its objects.
Maybe also include river BEDS."
  ;; #### NOTE: infinite scaling means that we do not have any elasticity.
  ;; Leaving things as they are, we would end up doing (* +/-∞ 0) below, which
  ;; is not good. However, the intended value of (* +/-∞ 0) is 0 here (again,
  ;; no elasticity) so we can get the same behavior by resetting SCALE to 0.
  (unless (slot-boundp line 'effective-scale)
    (setf (slot-value line 'effective-scale) (scale line)))
  (setq scale (if (numberp (effective-scale line)) (effective-scale line) 0))
  (setf (slot-value line 'pinned-objects)
	(loop :with x := 0 :with w
	      :with lineup := (lineup line)
	      :with last-elt := (aref lineup (1- (length lineup)))
	      :for elt
		:in (flatten-lineup lineup (start-idx line) (stop-idx line))
	      :if (eq elt :explicit-hyphenation-clue)
		:collect (make-hyphenation-clue line x)
	      :else :if (eq elt :hyphenation-clue)
		      :collect (make-hyphenation-clue line x nil)
	      :else :if (typep elt 'tfm:character-metrics)
		      :collect (pin-character elt line x)
		      :and :do (incf x (width elt))
	      :else :if (kernp elt)
		      :do (incf x (width elt))
	      :else :if (gluep elt)
		:do (setq w (width elt))
		:and :unless (zerop scale)
		       :do (incf w (if (> scale 0)
				     (* scale (stretch elt))
				     (* scale (shrink elt))))
		     :end
		:and :when (and beds (not (eq elt last-elt)))
		       ;; do not count a final glue as a river bed.
		       :collect (make-bed line (+ x (/ w 2)) w) :end
		:and :do (incf x w))))

(defgeneric line-properties (line)
  (:documentation "Return a string describing LINE's properties.")
  (:method-combination strnlcat :most-specific-last)
  (:method strnlcat ((line line))
    "Advertise LINE's width. This is the default method."
    (format nil "Width: ~Apt.~%Scale: ~A~:[~; (effective: ~A)~]"
      (float (width line))
      ($float (scale line))
      ($/= (scale line) (effective-scale line))
      ($float (effective-scale line)))))



;; ==========
;; Paragraphs
;; ==========

(defclass paragraph ()
  ((width :documentation "The paragraph's width."
	  :initarg :width
	  :reader width)
   (disposition :documentation "The paragraph's disposition."
		:initarg :disposition
		:reader disposition)
   (lineup :documentation "The paragraph's lineup."
	   :initform nil :initarg :lineup
	   :reader lineup)
   (pinned-lines :documentation "The paragraph's pinned lines."
		 :initform nil
		 :initarg :pinned-lines
		 :reader pinned-lines))
  (:documentation "The PARAGRAPH class."))

(defmethod break-points-# ((paragraph paragraph))
  "Return the number of break points in PARAGRAPH's lineup."
  (break-points-# (lineup paragraph)))

(defmethod theoretical-solutions-# ((paragraph paragraph))
  "Return the number of theoretical break solutions in PARAGRAPH's lineup."
  (theoretical-solutions-# (lineup paragraph)))

(defgeneric paragraph-properties (paragraph)
  (:documentation "Return a string describing PARAGRAPH's properties.")
  (:method-combination strnlcat :most-specific-last)
  (:method strnlcat ((paragraph paragraph))
    "Advertise PARAGRAPH's vertical dimensions and line number.
This is the default method."
    (format nil "Vertical size: ~Apt (height: ~Apt, depth: ~Apt).~@
		 ~A line~:P.~@
		 ~A breakpoints, ~A theoretical solutions (2^n)."
      (float (+ (height paragraph) (depth paragraph)))
      (float (height paragraph))
      (float (depth paragraph))
      (length (pinned-lines paragraph))
      (break-points-# paragraph)
      (theoretical-solutions-# paragraph))))
