(in-package :etap)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (net.didierverna.tfm:nickname-package))

(defconstant +initial-text+
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")

(defconstant +font-file+
  #p"/usr/local/texlive/2019/texmf-dist/fonts/tfm/adobe/times/ptmr.tfm")

(defclass state ()
  ((font :initform (tfm:load-font +font-file+) :reader font)
   (glue :reader glue)
   (disposition :initform :flush-left :accessor disposition)
   (features :initform (list) :accessor features)
   ;; 284.52756pt = 10cm
   (paragraph-width :initform 284 :accessor paragraph-width)
   (text :initform +initial-text+ :accessor text)
   (paragraph :accessor paragraph)))

(defstruct (kern :conc-name) value)
(defstruct (glue :conc-name) value stretch shrink)

(defmethod initialize-instance :after
    ((state state)
     &key
     &aux (font (font state))
	  (design-size (tfm:design-size font)))
  (setf (slot-value state 'glue)
	(make-glue :value (* (tfm:interword-space font) design-size)
		   :stretch (* (tfm:interword-stretch font) design-size)
		   :shrink (* (tfm:interword-shrink font) design-size))))


(defconstant +blanks+ '(#\Space #\Tab #\Newline))

(defun blankp (character) (member character +blanks+))

(defun lineup (state)
  (loop :with font := (font state)
	:with glue := (glue state)
	:with text := (string-trim +blanks+ (text state))
	:with length := (length text)
	:with i := 0

	:while (< i length)
	:for character := (tfm:get-character (char-code (aref text i)) font)

	:if (blankp (aref text i))
	  :collect glue
	  :and :do (setq i (position-if-not #'blankp text :start i))
	:else :if character
		:collect character
		:and :do (incf i)
	:else
	  :do (incf i)))

(defstruct (line-character :conc-name) x character-metrics)
(defstruct (paragraph-line :conc-name) y height depth characters)

(defun render
    (state
     &aux (design-size (tfm:design-size (font state)))
	  (lineup (lineup state))
	  (line (make-paragraph-line
		 :y 0
		 :characters
		 (loop :with x := 0
		       :for element :in lineup
		       :if (typep element 'tfm::character-metrics)
			 :collect (make-line-character
				   :x x :character-metrics element)
			 :and :do (incf x (* (tfm:width element) design-size))
		       :else :if (glue-p element)
			       :do (incf x (value element))))))
  (setf (height line)
	(* design-size
	   (apply #'max (mapcar #'tfm:height
			  (mapcar #'character-metrics (characters line))))))
  (setf (depth line)
	(* design-size
	   (apply #'max (mapcar #'tfm:depth
			  (mapcar #'character-metrics (characters line))))))
  (setf (paragraph state) line))
