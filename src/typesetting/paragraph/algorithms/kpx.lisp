;; This is my Knuth-Plass Extended, aka, KPX algorithm.

;; #### FIXME: this code is way too much redundant with the Knuth-Plass one.

(in-package :etap)

;; ==========================================================================
;; Specification
;; ==========================================================================

;; #### TODO: maybe we could introduce a basic value for similar demerits and
;; multiply it by the size of the similarity, rather than using a fixed value.

(defparameter *kpx-variants*
  '(:graph :dynamic))

(defparameter *kpx-variants-help-keys*
  '(:kpx-variant-graph :kpx-variant-dynamic))

(defparameter *kpx-tooltips*
  '(:kpx-variant-graph "Graph-based implementation."
    :kpx-variant-dynamic "Dynamic programming implementation."))


(defmacro define-kpx-caliber (name min default max)
  "Define a NAMEd KPX caliber with MIN, DEFAULT, and MAX values."
  `(define-caliber kpx ,name ,min ,default ,max))

(define-kpx-caliber line-penalty 0 10 100)
(define-kpx-caliber hyphen-penalty -10000 50 10000)
(define-kpx-caliber explicit-hyphen-penalty -10000 50 10000)
(define-kpx-caliber adjacent-demerits 0 10000 20000)
(define-kpx-caliber double-hyphen-demerits 0 10000 20000)
(define-kpx-caliber final-hyphen-demerits 0 5000 20000)
(define-kpx-caliber similar-demerits 0 5000 20000)
(define-kpx-caliber pre-tolerance -1 100 10000)
(define-kpx-caliber tolerance 0 200 10000)
(define-kpx-caliber emergency-stretch 0 0 20)
(define-kpx-caliber looseness -10 0 10)


(define-global-variables variant line-penalty
  hyphen-penalty explicit-hyphen-penalty
  adjacent-demerits double-hyphen-demerits final-hyphen-demerits
  similar-demerits
  pre-tolerance tolerance emergency-stretch looseness)


(defmacro calibrate-kpx (name &optional infinity)
  "Calibrate NAMEd KPX variable."
  `(calibrate kpx ,name :infinity ,infinity))

(defmacro default-kpx (name)
  "Default KPX NAMEd variable."
  `(default kpx ,name))




;; ==========================================================================
;; HList
;; ==========================================================================

(defmethod process-hlist
    (hlist disposition (algorithm (eql :kpx))
     &key ((:hyphen-penalty *hyphen-penalty*))
	  ((:explicit-hyphen-penalty *explicit-hyphen-penalty*)))
  "Adjust hyphen penalties in HLIST, and append the final glue to it."
  (calibrate-kpx hyphen-penalty t)
  (calibrate-kpx explicit-hyphen-penalty t)
  (mapc (lambda (item)
	  (when (discretionaryp item)
	    (setf (penalty item)
		  (if (pre-break item)
		    *hyphen-penalty*
		    *explicit-hyphen-penalty*))))
    hlist)
  (endpush (make-glue :stretch +∞ :penalty +∞) hlist)
  hlist)




;; ==========================================================================
;; Similarity (homeoteleutons and homeoarchies)
;; ==========================================================================

;; #### WARNING: this is good enough for now, but there are many limitations
;; to our approach to similarity.
;; 1. Comparing character metrics works only because we use a single font.
;; 2. Discarding kerns is probably not such a big deal, especially since we
;;    have a single font: the same sequence of characters would entail the
;;    same sequence of kerns.
;; 3. We stop at the first potential break point for several reasons (see
;;    below). This means that at least in theory, we might miss longer
;;    similarity sequences containing hyphenation points for instance. The
;;    reasons are the following:
;;    a. in the end-of-line case dynamic version, we can't remember whether
;;       it's been used by the previous line or not (although it's very
;;       unlikely). One exception would be hyphenation points with an infinite
;;       penalty, because these are not potential break points anymore.
;;       However,
;;    b. going through unused breakpoints requires recursively digging into
;;       the no-break constituents, hence some form of flattening. This is not
;;       currently implemented, but should probably be.
;; 5. We also stop at blanks, including unbreakable ones. That is because the
;;    only completely correct solution to similarity would be to compare
;;    vertical alignments as well, and this can only be done on lines (pinned
;;    objects) when scaling has been applied.
;; 6. In particular, this means that the end-of-line similarity doesn't
;;    currently work on the last two lines (which, at least in theory, could
;;    be both completely justified), because of the final infinite and
;;    unbreakable glue.
;;    #### TODO: in fact, I'm likely to remove this hack and treat the last
;;    line in a special way, so this might render this point obsolete.
;; 7. Finally, this approach works only on rectangular paragraphs.

(defun harray-bol-items (harray break-point)
  "Return the BOL items for an HARRAY line starting at BREAK-POINT.
This is the list of the first visible characters that lie between BREAK-POINT
and the next one."
  (unless (eopp break-point)
    (let ((idx (bol-idx break-point)) bol-items)
      (when (discretionaryp break-point)
	(setq bol-items (retain 'tfm:character-metrics (post-break break-point)
				:key #'type-of))
	(incf idx))
      (append bol-items
	      (loop :for i :from idx :upto (1- (length harray))
		    ;;                ╰► probably terminated sooner by :until
		    :for item := (aref harray i)
		    :until (break-point-p item)
		    :when (eq (type-of item) 'tfm:character-metrics)
		      :collect item)))))

(defun harray-eol-items (harray break-point)
  "Return the end-of-line items for an HARRAY line ending at BOUNDARY.
This is the list of the last visible characters (including a final hyphen if
the line is hyphenated) that lie between BOUNDARY and the previous break
point, in reverse order."
  (unless (eq break-point *bop*)
    (let ((idx (1- (eol-idx break-point))) eol-items)
      (when (discretionaryp break-point)
	(setq eol-items (retain 'tfm:character-metrics (pre-break break-point)
				:key #'type-of))
	(decf idx))
      (loop :for i :from idx :downto 0 ; probably terminated sooner by :until
	    :for item := (aref harray i)
	    :until (break-point-p item)
	    :when (eq (type-of item) 'tfm:character-metrics)
	      :do (push item eol-items))
      (nreverse eol-items))))




;; ==========================================================================
;; Graph Variant
;; ==========================================================================

;; The KPX graph variant does not need any specific data structures, because
;; similarity processing is done when creating the layouts, and we don't even
;; need to remember the BOL and EOL items outside of the path loop.

;; #### NOTE: this is currently left here for future re-implementation of last
;; line adjustments.

;; -----
;; Edges
;; -----

#+()(defmethod initialize-instance :after
    ((edge kpx-edge)
     &key harray start width
     &aux (boundary (boundary (destination edge))))
  "Initialize KPX EDGE's beginning and end of line items, adjust the scale."
  (setf (slot-value edge 'bol) (harray-bol start harray)
	(slot-value edge 'eol) (boundary-eol boundary harray))
  ;; #### HACK ALERT: at that point, the last edge is initialized normally for
  ;; a last line, that is, without the need for justification. The scaling
  ;; will thus be <= 0, and the other properties computed accordingly. If we
  ;; consider that adjusting the scaling of the last line a-posteriori
  ;; improves the quality, we don't want to also consider that as a local
  ;; deterioration of the quality (for example: slightly stretching an
  ;; underfull last line shouldn't be considered "bad"). Because of that, we
  ;; just leave the badness and local demerits as they are now. On the other
  ;; hand, we need to remember the scaling required to properly justify the
  ;; line now, because this value will serve as the maximum authorized scaling
  ;; for later adjustment (we can shrink as much as we want, but if we want to
  ;; stretch, we still don't want to make the last line overfull. In order to
  ;; do that (and this is where the hack is), we re-use the SCALE slot to push
  ;; that new value on top of the original one, by calling HARRAY-SCALE again,
  ;; but not counting the final (infinitely stretchable) glue. Another, less
  ;; hackish possibility would be to have a KPX-LAST-EDGE class with an
  ;; additional slot, but we can't CHANGE-CLASS here because we're within a
  ;; method accessing the instance's slots... so that would require additional
  ;; modifications elsewhere.
  (when (last-boundary-p boundary)
    (setf (slot-value edge 'scale)
	  (cons (harray-scale harray start (1- (stop-idx boundary)) width)
		(slot-value edge 'scale)))))

;; Last line ledge
#+()(defclass kpx-last-ledge (kp-ledge)
  ((scale :documentation "The adjusted last line scale."
	  :reader scale)
   (fitness-class :documentation "The adjusted last line fitness class."
		  :reader fitness-class))
  (:documentation "The KPX Last LEDGE class.
This class allows to override the last line scale and fitness-class on a
per-layout basis, in order to make it as close as possible to that of the the
one-before-last."))

;; #### NOTE: technically, this is not required, but it makes the code in
;; KPX-POSTPROCESS-LAYOUT more pleasant to read.
#+()(defmethod update-instance-for-different-class :after
    ((old kp-ledge) (new kpx-last-ledge) &key)
  "Initialize the scale slot to the edge's one."
  (setf (slot-value new 'scale) (scale (edge old))))

;; #### FIXME: no need to advertise the adjusted scale here because that's
;; what the advertised line properties contain (hence, the design of the LINE
;; hierarchy is broken; see comment atop GRAPH-LINE). Also, the adjusted
;; fitness class is likely to not be very different from the original one.
#+()(defmethod properties strnlcat ((ledge kpx-last-ledge))
  "Advertise KPX last LEDGE's adjusted fitness class."
  (format nil "Adjusted fitness class: ~A."
    (fitness-class-name (fitness-class ledge))))


;; -------
;; Layouts
;; -------

(defun kpx-graph-make-layout
    (breakup path
     &aux (harray (harray breakup))
	  (disposition (disposition breakup))
	  (disposition-type (disposition-type disposition))
	  (overshrink (getf (disposition-options disposition) :overshrink))
	  ;; #### NOTE: no emergency stretch counted here. See comment on top
	  ;; of KP-MAKE-JUSTIFIED-LINE.
	  (stretch-tolerance
	   (stretch-tolerance
	    (if (> (pass breakup) 1) *tolerance* *pre-tolerance*)))
	  (make-line
	   (case disposition-type
	     (:justified
	      (lambda (harray bol boundary demerits)
		(kp-make-justified-line harray bol boundary
		  stretch-tolerance overshrink demerits)))
	     (t ;; just switch back to normal spacing.
	      (lambda (harray bol boundary demerits)
		(make-instance 'kp-line
		  :harray harray :bol bol :boundary boundary
		  :demerits demerits)))))
	  (layout (make-instance 'kp-graph-layout
		    :breakup breakup
		    :demerits (demerits (first path))
		    :bads (if (numberp (badness (first path))) 0  1)))
	  line1)
  "Create a KPX layout for BREAKUP from graph PATH."
  ;; See warning in KP-CREATE-NODES about that.
  (when (zerop (fitness-class (first path)))
    (incf (slot-value layout 'demerits) *adjacent-demerits*))
  (setq line1 (funcall make-line harray *bop* (first path) (demerits layout)))
  (when (cdr path)
    (with-slots (demerits bads size) layout
      (loop :for boundary1 := (first path) :then boundary2
	    :for bol1 := (harray-bol-items harray *bop*) :then bol2
	    :for bol2 := (harray-bol-items harray (break-point boundary1))
	    :for eol1 := (harray-eol-items harray (break-point (first path)))
	      :then eol2
	    :for boundary2 :in (cdr path)
	    :for eol2 := (harray-eol-items harray (break-point boundary2))
	    :for finalp := (eopp boundary2)
	    :do (incf size)
	    :unless (numberp (badness boundary2)) :do (incf bads)
	    :do (incf demerits (demerits boundary2))
	    ;; See comment in dynamic version. Do not consider the very
	    ;; rare case where the paragraph ends with an explicit hyphen.
	    :when (and (not finalp)
		       (hyphenated boundary1)
		       (hyphenated boundary2))
	      :do (incf demerits *double-hyphen-demerits*)
	    :when (and finalp (hyphenated boundary1))
	      :do (incf demerits *final-hyphen-demerits*)
	    :when (> (abs (- (fitness-class boundary1)
			     (fitness-class boundary2)))
		     1)
	      :do (incf demerits *adjacent-demerits*)
	     ;; #### NOTE: for now, I'm considering that hyphenated
	     ;; similarities are even worse than regular ones, so we will
	     ;; apply both similar and double-hyphen demerits.
	     ;; #### FIXME: see with Thomas whether 2 is acceptable.
	    :when (>= (compare bol1 bol2) 2)
	      :do (incf demerits *similar-demerits*)
	     :when (>= (compare eol1 eol2) 2)
		   :do (incf demerits *similar-demerits*)
	    :collect (funcall make-line
		       harray (break-point boundary1) boundary2 demerits)
	      :into lines
	    :finally (setf (slot-value layout 'lines) (cons line1 lines)))))
  layout)

(defun kpx-graph-make-layouts (breakup graph)
  "Make KPX GRAPH layouts for BREAKUP."
  (mapcar (lambda (path) (kpx-graph-make-layout breakup path))
    (make-graph-paths graph)))


;; -------
;; Breakup
;; -------

(defun kpx-graph-break-harray
    (harray disposition width
     &aux (breakup (make-instance 'kp-graph-breakup
		     :harray harray :disposition disposition :width width)))
  "Break HARRAY with the Knuth-Plass algorithm, graph version."
  (unless (zerop (length harray))
    (let (graph layouts)

      ;; Pass 1, never final.
      (when ($<= 0 *pre-tolerance*)
	(setf (slot-value breakup 'pass) 1)
	(setq graph (make-graph harray width
				(lambda (harray bol width)
				  (kp-get-boundaries
				   harray bol width *pre-tolerance*))))
	(when (gethash *bop* graph)
	  (setq layouts (sort (kpx-graph-make-layouts breakup graph)
			    #'< :key #'demerits))
	  (unless (zerop *looseness*)
	    (setq layouts (kp-remove-unloose-layouts layouts)))))

      ;; Pass 2, maybe final.
      (unless layouts
	(let ((final (zerop *emergency-stretch*)))
	  (setf (slot-value breakup 'pass) 2)
	  (setq graph (make-graph harray width
				  (lambda (harray bol width)
				    (kp-get-boundaries
				     harray bol width *tolerance* t final))))
	  (when (gethash *bop* graph)
	    (cond (final
		   (setq layouts (sort (kpx-graph-make-layouts breakup graph)
				     #'kp-graph-layout-<))
		   (unless (zerop *looseness*)
		     (setq layouts (kp-sort-layouts-by-looseness layouts))))
		  (t
		   (setq layouts (sort (kpx-graph-make-layouts breakup graph)
				     #'< :key #'demerits))
		   (unless (zerop *looseness*)
		     (setq layouts (kp-remove-unloose-layouts layouts))))))))

      ;; Pass 3, always final.
      (unless layouts
	(incf (slot-value breakup 'pass))
	(setq graph (make-graph harray width
				(lambda (harray bol width)
				  (kp-get-boundaries
				   harray bol width *tolerance*
				   t t *emergency-stretch*))))
	(setq layouts
	      (sort (kpx-graph-make-layouts breakup graph) #'kp-graph-layout-<))
	(unless (zerop *looseness*)
	  (setq layouts (kp-sort-layouts-by-looseness layouts))))

      ;; We're done here.
      (setf (slot-value breakup 'graph) graph)
      (setf (slot-value breakup 'layouts)
	    (make-array (length layouts) :initial-contents layouts))))
  breakup)




;; ==========================================================================
;; Dynamic Variant
;; ==========================================================================

;; Contrary to the graph variant, the dynamic one needs to remember the BOL
;; and EOL items in the nodes, so we need a specific subclass for that.

(defclass kpx-node (kp-node)
  ((eol-items
    :documentation "This node's EOL items."
    :initarg :eol-items :reader eol-items)
   (bol-items
    :documentation "This node's BOL items."
    :initarg :bol-items :reader bol-items))
   (:documentation "The KPX Node class."))

#+()(defstruct (kpx-last-node (:constructor kpx-make-last-node)
			  (:include kpx-node))
  original-scale original-fitness-class)


;; ---------------
;; Boundary lookup
;; ---------------

(defun kpx-try-break
    (break-point nodes harray width make-node threshold final emergency-stretch
     &aux (bol-items (harray-bol-items harray break-point))
	  (eol-items (harray-eol-items harray break-point))
	  last-deactivation new-nodes)
  "Examine BREAK-POINT and update active NODES accordingly."
  (maphash
   (lambda (key node
	    &aux (bol (key-break-point key)) ; also available in the node
		 (boundary (make-instance 'kp-boundary
			     :harray harray :bol bol :break-point break-point
			     :target width :extra emergency-stretch)))
     ;; #### WARNING: we must deactivate all nodes when we reach the
     ;; paragraph's end. TeX does this by adding a forced break at the end but
     ;; this is a "dangling" penalty, whereas ours are properties of break
     ;; points. This is why we need to check explicitly for the EOP below.
     (when (or ($< (scale boundary) -1)
	       (eq (penalty boundary) -∞)
	       (eopp boundary))
       (setq last-deactivation (cons key node))
       (remhash key nodes))
     (when (and ($<= -1 (scale boundary)) ($<= (badness boundary) threshold))
       (let ((demerits (+ (demerits node) (demerits boundary))))
	 ;; #### WARNING: we must use the key's fitness class rather than the
	 ;; node's one below, as accessing the node's one would break on the
	 ;; BOP node. Besides, we also save a couple of accessor calls that
	 ;; way.
	 (when (> (abs (- (fitness-class boundary) (key-fitness-class key))) 1)
	   (incf demerits *adjacent-demerits*))
	 ;; #### NOTE: according to #859, TeX doesn't consider the admittedly
	 ;; very rare and weird case where a paragraph would end with an
	 ;; explicit hyphen. As stipulated in #829, for the purpose of
	 ;; computing demerits, the end of the paragraph is always regarded as
	 ;; virtually hyphenated, and in case the previous line (really) is
	 ;; hyphenated, the value of final-hyphen-demerits is used instead of
	 ;; double-hyphen-demerits. One could consider using
	 ;; double-hyphen-demerits when there actually is a final hyphen, but
	 ;; on the other hand, the final line is rarely justified so the two
	 ;; hyphens are very unlikely to create a ladder.
	 (when (discretionaryp bol)
	   (if (eopp boundary)
	     (incf demerits *final-hyphen-demerits*)
	     (when (discretionaryp (break-point boundary))
	       (incf demerits *double-hyphen-demerits*))))
	 ;; #### NOTE: for now, I'm considering that hyphenated similarities
	 ;; are even worse than regular ones, so we will apply both similar
	 ;; and double-hyphen demerits.
	 ;; #### FIXME: see with Thomas whether 2 is acceptable.
	 (when (>= (compare (eol-items node) eol-items) 2)
	   (incf demerits *similar-demerits*))
	 (when (>= (compare (bol-items node) bol-items) 2)
	   (incf demerits *similar-demerits*))
	 (let* ((new-key (make-key break-point
				   (1+ (key-line-number key))
				   (fitness-class boundary)))
		(previous (find new-key new-nodes :test #'equal :key #'car))
		(new-node
		  (when (or (not previous)
			    ;; #### NOTE: the inclusive inequality below is
			    ;; conformant with what TeX does in #855.
			    ;; Concretely, it makes the KP algorithm greedy in
			    ;; some sense: in case of demerits equality, TeX
			    ;; keeps the last envisioned solution. On the
			    ;; other hand, we're in fact not doing exactly the
			    ;; same thing because we're using MAPHASH and the
			    ;; order of the nodes in the hash table is not
			    ;; deterministic.
			    (<= demerits (demerits (cdr previous))))
		    (funcall make-node
		      harray bol boundary demerits node eol-items bol-items))))
	   (when new-node
	     (if previous
	       (setf (cdr previous) new-node)
	       (push (cons new-key new-node) new-nodes)))))))
   nodes)
  (when (and final (zerop (hash-table-count nodes)) (null new-nodes))
    (let* ((bol (key-break-point (car last-deactivation)))
	   (boundary (make-instance 'kp-boundary
		       :harray harray
		       :bol bol
		       :break-point break-point
		       :target width
		       :extra emergency-stretch)))
      ;; #### NOTE: in this situation, TeX sets the local demerits to 0 by
      ;; checking the artificial_demerits flag (#854, #855). The KP-BOUNDARY
      ;; initialization protocol takes care of this. In any case, we can also
      ;; just reuse the previous total demerits in the new node.
      (setq new-nodes
	    (list
	     (cons (make-key break-point
			     (1+ (key-line-number (car last-deactivation)))
			     (fitness-class boundary))
		   (funcall make-node
		     harray bol boundary (demerits (cdr last-deactivation))
		     (cdr last-deactivation) eol-items bol-items))))))
  (mapc (lambda (new-node)
	  (setf (gethash (car new-node) nodes) (cdr new-node)))
    new-nodes))

(defun kpx-make-justified-node
    (harray bol boundary stretch-tolerance overshrink demerits previous
     eol-items bol-items
     &aux (scale (scale boundary)))
  "KPX dynamic version of `make-line' for justified lines."
  (multiple-value-bind (theoretical effective)
      (actual-scales scale
	:stretch-tolerance stretch-tolerance
	:overshrink overshrink
	:overstretch t)
    (make-instance 'kpx-node
      :harray harray :bol bol :boundary boundary
      :scale theoretical :effective-scale effective
      :demerits demerits :previous previous
      :eol-items eol-items :bol-items bol-items)))

(defun kpx-create-nodes
    (breakup
     &aux (harray (harray breakup))
	  (pass (pass breakup))
	  (width (width breakup))
	  (disposition (disposition breakup))
	  (disposition-type (disposition-type disposition))
	  (overshrink (getf (disposition-options disposition) :overshrink))
	  (threshold (if (> pass 1) *tolerance* *pre-tolerance*))
	  ;; #### NOTE: no emergency stretch counted here. See comment on top
	  ;; of KP-MAKE-JUSTIFIED-LINE.
	  (stretch-tolerance (stretch-tolerance threshold))
	  (hyphenate (> pass 1))
	  (final (case pass
		   (1 nil)
		   (2 (zerop *emergency-stretch*))
		   (3 t)))
	  (emergency-stretch (when final *emergency-stretch*))
	  (nodes (make-hash-table :test #'equal))
	  (make-node
	   (case disposition-type
	     (:justified
	      (lambda
		  (harray bol boundary demerits previous eol-items bol-items)
		(kpx-make-justified-node harray bol boundary
		  stretch-tolerance overshrink demerits previous
		  eol-items bol-items)))
	     (t ;; just switch back to normal spacing.
	      (lambda
		  (harray bol boundary demerits previous eol-items bol-items)
		(make-instance 'kpx-node
		  :harray harray :bol bol :boundary boundary
		  :demerits demerits :previous previous
		  :eol-items eol-items :bol-items bol-items))))))
  "Create Knuth-Plass BREAKUP's dynamic nodes."
  (setf (gethash *kp-bop-key* nodes)
	;; #### NOTE: we can't use *KP-BOP-NODE* here because we need to
	;; remember the eol and bol items which are harray-dependent.
	(make-instance 'kpx-node
	  :boundary (make-instance 'boundary :break-point *bop*)
	  :demerits 0
	  :eol-items nil :bol-items (harray-bol-items harray *bop*)))
  (loop :for break-point := (next-break-point harray)
	  :then (next-break-point harray break-point)
	:while break-point
	:when (and ($< (penalty break-point) +∞)
		   (or hyphenate (not (hyphenation-point-p break-point))))
	  :do (kpx-try-break break-point nodes harray width make-node
			    threshold final emergency-stretch))
  (unless (zerop (hash-table-count nodes)) nodes))



;; -----------------
;; Lines computation
;; -----------------

#+()(defclass kpx-last-dynamic-line (kp-dynamic-line)
  ((original-scale :documentation "The last line's original scale."
		   :initarg :original-scale
		   :reader original-scale)
   (original-fitness-class
    :documentation "The last line's original fitness class."
    :initarg :original-fitness-class
    :reader original-fitness-class))
  (:documentation "The KPX Last Dynamic Line class."))

#+()(defmethod properties strnlcat ((line kpx-last-dynamic-line) &key)
  "Advertise KPX last dynamic LINE's original scale and fitness class."
  (format nil "Original scale: ~A.~@
	       Original fitness class: ~A."
    ($float (original-scale line))
    (fitness-class-name (original-fitness-class line))))


;; ------------------------
;; Breakup specialization
;; ------------------------

;; #### NOTE: according to #872, TeX will attempt to match a non-zero
;; looseness exactly, or try another pass unless it's already the final one. I
;; got that wrong for quite some time...
(defun kpx-dynamic-break-harray
    (harray disposition width
     &aux (breakup (make-instance 'kp-dynamic-breakup
		     :harray harray :disposition disposition :width width)))
  "Break HARRAY with the KPX algorithm, dynamic programming version."
  (unless (zerop (length harray))
    (let (nodes layouts)

      ;; Pass 1, never final.
      (when ($<= 0 *pre-tolerance*)
	(setf (slot-value breakup 'pass) 1)
	(setq nodes (kpx-create-nodes breakup))
	(when nodes
	  (setq layouts (kp-dynamic-make-layouts breakup nodes))
	  (unless (zerop *looseness*)
	    (setq layouts (kp-remove-unloose-layouts layouts)))))

      ;; Pass 2, maybe final.
      (unless layouts
	(let ((final (zerop *emergency-stretch*)))
	  (setf (slot-value breakup 'pass) 2)
	  (setq nodes (kpx-create-nodes breakup))
	  (when nodes
	    (setq layouts (kp-dynamic-make-layouts breakup nodes))
	    (unless (zerop *looseness*)
	      (setq layouts
		    (if final
		      (kp-sort-layouts-by-looseness layouts)
		      (kp-remove-unloose-layouts layouts)))))))

      ;; Pass 3, always final.
      (unless nodes
	(incf (slot-value breakup 'pass))
	(setq nodes (kpx-create-nodes breakup))
	(setq layouts (kp-dynamic-make-layouts breakup nodes))
	(unless (zerop *looseness*)
	  (setq layouts (kp-sort-layouts-by-looseness layouts))))

      ;; We're done here.
      (setf (slot-value breakup 'layouts)
	    (make-array (length layouts) :initial-contents layouts))))
  breakup)




;; ==========================================================================
;; Variant Dispatch
;; ==========================================================================

(defmethod break-harray
    (harray disposition width (algorithm (eql :kpx))
     &key ((:variant *variant*))
	  ((:line-penalty *line-penalty*))
	  ((:adjacent-demerits *adjacent-demerits*))
	  ((:double-hyphen-demerits *double-hyphen-demerits*))
	  ((:final-hyphen-demerits *final-hyphen-demerits*))
	  ((:similar-demerits *similar-demerits*))
	  ((:pre-tolerance *pre-tolerance*))
	  ((:tolerance *tolerance*))
	  ((:emergency-stretch *emergency-stretch*))
	  ((:looseness *looseness*)))
  "Break HARRAY with the KPX algorithm."
  (default-kpx variant)
  (calibrate-kpx line-penalty)
  (calibrate-kpx adjacent-demerits)
  (calibrate-kpx double-hyphen-demerits)
  (calibrate-kpx final-hyphen-demerits)
  (calibrate-kpx similar-demerits)
  (calibrate-kpx pre-tolerance :positive)
  (calibrate-kpx tolerance :positive)
  (calibrate-kpx emergency-stretch)
  (calibrate-kpx looseness)
  (funcall (ecase *variant*
	     (:graph #'kpx-graph-break-harray)
	     (:dynamic #'kpx-dynamic-break-harray))
    harray disposition width))
