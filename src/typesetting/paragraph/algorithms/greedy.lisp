(in-package :etap)

;; #### TODO: until renditions are reified as actual objects of some kind
;; instead of just lists of pinned lines, a greedy breakup cannot make the
;; distinction between no rendition because the harray is empty, or no
;; rendition because no acceptable solution. This is not currently a problem
;; because our greedy algorithms never refuse to typeset, but could be in the
;; future.

(defun make-greedy-lines (harray width get-boundary make-line)
  "Make HARRAY lines for a paragraph of WIDTH.
If HARRAY is empty, return NIL.
This function processes HARRAY in a greedy way:
- (GET-BOUNDARY HARRAY BOL WIDTH) is called to get the end of line boundary
  for a line starting at BOL,
- (MAKE-LINE HARRAY BOL BOUNDARY) is called to make the line in
  question."
  (unless (zerop (length harray))
    (loop :for bol := *bop* :then (break-point boundary)
	  :for boundary := (funcall get-boundary harray bol width)
	  :while boundary
	  :collect (funcall make-line harray bol boundary))))


(defclass greedy-breakup (breakup)
  ((rendition :documentation "This breakup's rendition."
	      :initform nil :reader rendition))
  (:documentation "The Greedy Breakup class.
This class is used by greedy algorithms to store their only solution."))

(defmethod initialize-instance :after ((breakup greedy-breakup) &key lines)
  "Pin LINES in BREAKUP's rendition."
  (setf (slot-value breakup 'rendition)
	(pin-lines lines
		   (disposition-type (disposition breakup))
		   (width breakup))))

(defun make-greedy-breakup
    (harray disposition width get-boundary make-line)
  "Make a greedy breakup of HARRAY for a DISPOSITION paragraph of WIDTH.
See `make-greedy-lines' for further information."
  (make-instance 'greedy-breakup
    :disposition disposition
    :width width
    :lines (make-greedy-lines harray width get-boundary make-line)))


(defmethod properties strnlcat ((breakup greedy-breakup) &key rendition)
  "Return a string advertising greedy BREAKUP's properties."
  (when rendition
    (assert (zerop rendition))
    (properties (rendition breakup))))


(defmethod renditions-# ((breakup greedy-breakup))
  "Return greedy BREAKUP's renditions number (0 or 1)."
  (if (rendition breakup) 1 0))

(defmethod get-rendition (nth (breakup greedy-breakup))
  "Return the only greedy BREAKUP's rendition."
  (assert (and (rendition breakup) (zerop nth)))
  (rendition breakup))
