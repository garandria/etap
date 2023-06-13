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

(defun actual-scales (scale &key (shrink-tolerance -1) (stretch-tolerance 1)
				 (overshrink nil) (overstretch nil))
  "Compute the actual scales for a line, based on required SCALE.
This function returns two values.
- The theoretical scale computed by the algorithm in use. This value depends
  on the algorithm s SHRINK / STRETCH-TOLERANCE (-1 / 1 by default).
- The effective scale, used to pin the line's objects. This value further
  depends on the OVERSHRINK / OVERSTRETCH options (nil by default)."
  (let ((theoretical-scale scale) (effective-scale scale))
    (cond ((i< scale 0)
	   (setq theoretical-scale (imax theoretical-scale shrink-tolerance))
	   (unless overshrink (setq effective-scale theoretical-scale)))
	  ((i> scale 0)
	   (setq theoretical-scale (imin theoretical-scale stretch-tolerance))
	   (unless overstretch (setq effective-scale theoretical-scale))))
    (values theoretical-scale effective-scale)))



;; ==============
;; Pinned Objects
;; ==============

(defclass pinned-character (pinned)
  ((character-metrics :initarg :character-metrics :accessor character-metrics
		      :documentation "The pinned character."))
  (:documentation "The PINNED-CHARACTER class.
The character's 2D position is relative to the line it belongs to."))

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

(defun pin-character (character &rest initargs &key x y)
  "Pin CHARACTER at position (X, Y)."
  (declare (ignore x y))
  (apply #'make-instance 'pinned-character
    :character-metrics character initargs))


(defclass pinned-hyphenation-clue (pinned)
  ((explicitp
    :initform t :initarg :explicit :reader explicitp
    :documentation
    "Whether this hyphenation clue comes from an explicit hyphen."))
  (:documentation "The PINNED-HYPHENATION-CLUE class.
The hyphenation clue's 2D position is relative to the line it belongs to."))

(defun pinned-hyphenation-clue-p (object)
  "Return T if OBJECT is a pinned hyphenation clue."
  (typep object 'pinned-hyphenation-clue))

(defmethod width ((clue pinned-hyphenation-clue))
  "Return pinned hyphenation clue's width (0)."
  0)

(defmethod height ((clue pinned-hyphenation-clue))
  "Return pinned hyphenation clue's height (0)."
  0)

(defmethod depth ((clue pinned-hyphenation-clue))
  "Return pinned hyphenation clue's depth (0)."
  0)

(defun pin-hyphenation-clue (x &optional (explicit t))
  "Pin possibly EXPLICIT hyphenation clue at (X, 0)."
  (make-instance 'pinned-hyphenation-clue :x x :explicit explicit))



;; =====
;; Lines
;; =====

(defclass line ()
  ((lineup :initarg :lineup :reader lineup
	   :documentation "The corresponding lineup.")
   (start-idx :initarg :start-idx :reader start-idx
	      :documentation "This line's start index in LINEUP.")
   (stop-idx :initarg :stop-idx :reader stop-idx
	     :documentation "This line's stop index in LINEUP.")
   (scale :initform 0 :initarg :scale :reader scale
	  :documentation "The line'scale, as computed by the algorithm.
It may be different from the effective scale used to pin the objects,
depending on the algorithm itself, and on the Overstretch and Overshrink
disposition options).")
   (effective-scale
    :initarg :effective-scale :reader effective-scale
    :documentation "The line's effective scale, used for pinning the objects.
It may be different from the scale computed by the algorithm in use, depending
on the algorithm itself, and on the Overstretch and Overshrink disposition
options).")
   (pinned-objects :reader pinned-objects
		   :documentation "The list of pinned objects."))
  (:documentation "The LINE class.
A line contains a list of pinned objects (currently, characters and
hyphenation clues). The objects are positioned relatively to the line's
origin. A line also remembers its scale factor."))

(defgeneric hyphenated (object)
  (:documentation "Whether OBJECT is hyphenated.
Possible values are nil, :explicit, or :implicit.")
  (:method
      ((line line) &aux (element (aref (lineup line) (1- (stop-idx line)))))
    "Whether LINE is hyphenated.
Possible values are nil, :explicit, or :implicit."
    (when (hyphenation-point-p element)
      (if (explicitp element) :explicit :implicit))))

(defmethod penalty
    ((line line) &aux (element (aref (lineup line) (1- (stop-idx line)))))
  "Return LINE's penalty."
  (if (break-point-p element) (penalty element) 0))

;; #### FIXME: probably rename this to EFFECTIVE-WIDTH.
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

(defmethod initialize-instance :after ((line line) &key &aux scale)
  "Possibly initialize the LINE's effective scale, and pin its objects."
  ;; #### NOTE: infinite scaling means that we do not have any elasticity.
  ;; Leaving things as they are, we would end up doing (* +/-∞ 0) below, which
  ;; is not good. However, the intended value of (* +/-∞ 0) is 0 here (again,
  ;; no elasticity) so we can get the same behavior by resetting SCALE to 0.
  (unless (slot-boundp line 'effective-scale)
    (setf (slot-value line 'effective-scale) (scale line)))
  (setq scale (if (numberp (effective-scale line)) (effective-scale line) 0))
  (setf (slot-value line 'pinned-objects)
	(loop :with x := 0
	      :for elt :in (flatten-lineup
			    (lineup line) (start-idx line) (stop-idx line))
	      :if (eq elt :explicit-hyphenation-clue)
		:collect (pin-hyphenation-clue x)
	      :else :if (eq elt :hyphenation-clue)
		      :collect (pin-hyphenation-clue x nil)
	      :else :if (typep elt 'tfm:character-metrics)
		      :collect (pin-character elt :x x)
		      :and :do (incf x (width elt))
	      :else :if (kernp elt)
		      :do (incf x (width elt))
	      :else :if (gluep elt)
		      :do (incf x (width elt))
		      :and :unless (zerop scale)
			     :do (incf x (if (> scale 0)
					   (* scale (stretch elt))
					   (* scale (shrink elt)))))))

(defun strnlcat (&rest strings)
  "Concatenate STRINGS, inserting newlines in between."
  (with-output-to-string (stream nil :element-type 'character)
    (loop :for remainder :on strings
	  :do (princ (car remainder) stream)
	  :when (cdr remainder) :do (terpri stream))))

(define-method-combination strnlcat
  :documentation "The STRNLCAT method combination."
  :operator strnlcat :identity-with-one-argument t)

(defgeneric line-properties (line)
  (:documentation "Return a string describing LINE's properties.")
  (:method-combination strnlcat :most-specific-last)
  (:method strnlcat ((line line))
    "Advertise LINE's width. This is the default method."
    (format nil "Width: ~Apt.~%Scale: ~A~:[~; (effective: ~A)~]"
      (float (width line))
      (ifloat (scale line))
      (i/= (scale line) (effective-scale line))
      (ifloat (effective-scale line)))))
