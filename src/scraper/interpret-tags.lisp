(in-package :cscrape)

(define-condition bad-cl-defun/defmethod ()
  ((tag :initarg :tag :accessor tag)
   (other-tag :initarg :other-tag :accessor other-tag))
  (:report (lambda (condition stream)
             (format stream "Error at ~a interpreting tag ~a ~a the tag ~a at ~a is too far away"
                     (tags:source-pos (tag condition))
                     (tags:tag-code (tag condition))
                     (tags:identifier (tag condition))
                     (tags:tag-code (other-tag condition))
                     (tags:source-pos (other-tag condition))))))



(defclass expose-code ()
  ((file% :initarg :file% :accessor file%)
   (line% :initarg :line% :accessor line%)
   (character-offset% :initarg :character-offset% :accessor character-offset%)
   (namespace% :initform nil :initarg :namespace% :accessor namespace%)
   (lisp-name% :initform nil :initarg :lisp-name% :accessor lisp-name%)
   (lambda-list% :initform nil :initarg :lambda-list% :accessor lambda-list%)
   (declare% :initform nil :initarg :declare% :accessor declare%)
   (docstring% :initform nil :initarg :docstring% :accessor docstring%)))

(defclass package-to-create ()
  ((name% :initarg :name% :accessor name%)
   (file% :initarg :file% :accessor file%)
   (line% :initarg :line% :accessor line%)
   (character-offset% :initarg :character-offset% :accessor character-offset%)
   (packages-to-use% :initarg :packages-to-use% :accessor packages-to-use%)
   (nicknames% :initarg :nicknames% :accessor nicknames%)))

(defclass function-mixin ()
  ((function-name% :initform nil :initarg :function-name% :accessor function-name%)))

(defclass expose-internal-function (expose-code function-mixin)
  ((signature% :initform nil :initarg :signature% :accessor signature%)
   (provide-declaration% :initform t :initarg :provide-declaration% :accessor provide-declaration%)))

(defclass expose-external-function (expose-code function-mixin)
  ((pointer% :initform nil :initarg :pointer% :accessor pointer%)))

(defclass method-mixin ()
  ((class% :initform nil :initarg :class% :accessor class%)
   (method-name% :initform nil :initarg :method-name% :accessor method-name%)))

(defclass expose-internal-method (expose-code method-mixin)
  ((signature% :initform nil :initarg :signature% :accessor signature%)))

(defclass expose-external-method (expose-code method-mixin)
  ((pointer% :initform nil :initarg :pointer% :accessor pointer%)))

(defclass exposed-class ()
  ((file% :initarg :file% :accessor file%)
   (line% :initarg :line% :accessor line%)
   (character-offset% :initarg :character-offset% :accessor character-offset%)
   (meta-class% :initarg :meta-class% :accessor meta-class%)
   (docstring% :initarg :docstring% :accessor docstring%)
   (package% :initarg :package% :accessor package%)
   (class-tag% :initarg :class-tag% :accessor class-tag%)
   (class-key% :initarg :class-key% :accessor class-key%)
   (base% :initarg :base% :accessor base%)
   (lisp-name% :initarg :lisp-name% :accessor lisp-name%)
   (methods% :initarg :methods% :accessor methods%)))

(defclass exposed-internal-class (exposed-class) ())
(defclass exposed-external-class (exposed-class) ())

(defclass expose-symbol ()
  ((lisp-name% :initarg :lisp-name% :accessor lisp-name%)
   (c++-name% :initarg :c++-name% :accessor c++-name%)
   (namespace% :initarg :namespace% :accessor namespace%)
   (package% :initarg :package% :accessor package%)
   (package-str% :initarg :package-str% :accessor package-str%)
   (exported% :initform t :initarg :exported% :accessor exported%)
   (shadow% :initform nil :initarg :shadow% :accessor shadow%)))

(defclass expose-external-symbol (expose-symbol) ())
(defclass expose-shadow-external-symbol (expose-external-symbol) ())
(defclass expose-internal-symbol (expose-symbol) ())
(defclass expose-intern-symbol (expose-symbol) ())

(defclass begin-enum ()
  ((file% :initarg :file% :accessor file%)
   (line% :initarg :line% :accessor line%)
   (character-offset% :initarg :character-offset% :accessor character-offset%)
   (type% :initarg :type% :accessor type%)
   (symbol% :initarg :symbol% :accessor symbol%)
   (description% :initarg :description% :accessor description%)))

(defclass value-enum ()
  ((file% :initarg :file% :accessor file%)
   (line% :initarg :line% :accessor line%)
   (character-offset% :initarg :character-offset% :accessor character-offset%)
   (symbol% :initarg :symbol% :accessor symbol%)
   (value% :initarg :value% :accessor value%)))

(defclass completed-enum ()
  ((begin-enum% :initarg :begin-enum% :accessor begin-enum%)
   (values% :initarg :values% :accessor values%)))

   
(defun lispify-class-name (tag packages)
  (format nil "core::magic_name(\"~a:~a\")" (gethash (tags:package% tag) packages) (tags:class-symbol% tag)))

(defun maybe-override-name (namespace-tag override-name-tag name packages)
  "* Arguments
- override-name-tag :: A name-tag.
- name :: A string
- packages :: A map of namespace and C++ package names to package name strings.
* Description
If override-name-tag is not nil then return its value, otherwise return name"
  (if (null override-name-tag)
      name
      (etypecase override-name-tag
        (tags:lispify-name-tag
         (packaged-name namespace-tag override-name-tag packages))
        (tags:name-tag
         (packaged-name namespace-tag override-name-tag packages))
        (tags:pkg-name-tag
         (format nil "core::magic_name(~s,~s)"
                 (tags:name% override-name-tag)
                 (gethash (tags:package% override-name-tag) packages))))))


(defun order-packages-by-use (packages)
  (declare (optimize debug))
  (let ((unsorted (make-hash-table :test #'eq))
        sorted)
    (dolist (p packages)
      (setf (gethash p unsorted) t))
    (loop
       (block restart-top
         (maphash (lambda (p dummy)
                    (declare (ignore dummy))
                    (let ((missing-used nil))
                      (dolist (u (packages-to-use% p))
                        (unless (member u sorted :key (lambda (x) (name% x)) :test #'string=)
                          (setq missing-used t)))
                      (unless missing-used
                        (push p sorted)
                        (remhash p unsorted)
                        (return-from restart-top))))
                  unsorted)
         (if (= (hash-table-count unsorted) 0)
             (return-from order-packages-by-use (nreverse sorted))
             (error "There is a circular use dependency for the packages ~s~%Sorted packages ~s"
                    (let (problem-packages)
                      (maphash (lambda (k v)
                                 (declare (ignore v))
                                 (push (list (name% k) (list :use (packages-to-use% k) )) problem-packages))
                               unsorted)
                      problem-packages)
                    (reverse sorted)))))))


(defun check-symbol-against-previous (symbol previous-symbols)
  (let* ((key (format nil "~a/~a" (package% symbol) (lisp-name% symbol)))
         (previous (gethash key previous-symbols)))
    (if previous
        (progn
          (when (not (eq (exported% symbol) (exported% previous)))
            (warn "The symbol ~a in package ~a was declared twice with different export status - c++-names ~a ~a" (lisp-name% symbol) (package% symbol) (c++-name% symbol) (c++-name% previous)))
          (when (not (eq (shadow% symbol) (shadow% previous)))
            (warn "The symbol ~a in package ~a was declared twice with different shadow status - c++-names ~a ~a" (lisp-name% symbol) (package% symbol) (c++-name% symbol) (c++-name% previous))))
        (setf (gethash key previous-symbols) symbol))))

(defun interpret-tags (tags)
  (declare (optimize (debug 3)))
  (let ((source-info (gather-source-files tags)))
    (calculate-character-offsets source-info))
  (let (cur-lambda
        cur-name
        cur-docstring
        cur-declare
        cur-package-nickname-tags
        cur-package-use-tags
        cur-namespace-tag
        cur-class
        cur-meta-class
        cur-begin-enum
        cur-values
        enums
        (namespace-to-assoc (make-hash-table :test #'equal))
        (package-to-assoc (make-hash-table :test #'equal))
        (packages (make-hash-table :test #'equal)) ; map ns/package to package string
        (packages-to-create nil)
        (classes (make-hash-table :test #'equal))
        functions symbols
        (previous-symbols (make-hash-table :test #'equal)))
    (declare (special namespace-to-assoc package-to-assoc packages))
    (dolist (tag tags)
      (etypecase tag
        (tags:namespace-package-association-tag
         (setf (gethash (tags:namespace% tag) namespace-to-assoc) tag)
         (setf (gethash (tags:package% tag) package-to-assoc) tag)
         (setf (gethash (tags:namespace% tag) packages) (tags:package-str% tag))
         (setf (gethash (tags:package% tag) packages) (tags:package-str% tag))
         (pushnew (make-instance 'package-to-create
                                 :file% (tags:file% tag)
                                 :line% (tags:line% tag)
                                 :character-offset% (tags:character-offset% tag)
                                 :name% (tags:package-str% tag)
                                 :packages-to-use% (mapcar (lambda (x) (tags:name% x)) cur-package-use-tags)
                                 :nicknames% (mapcar (lambda (x) (tags:name% x)) cur-package-nickname-tags))
                  packages-to-create
                  :test #'string=
                  :key (lambda (x) (name% x)))
         (setf cur-package-use-tags nil
               cur-package-nickname-tags nil))
        (tags:namespace-tag
         (setf cur-namespace-tag tag))
        (tags:name-tag
         (setf cur-name tag))
        (tags:meta-class-tag
         (setf cur-meta-class tag))
        (tags:lispify-name-tag
         (setf cur-name tag))
        (tags:pkg-name-tag
         (setf cur-name tag))
        (tags:lambda-tag
         (setf cur-lambda tag))
        (tags:docstring-tag
         (setf cur-docstring tag))
        (tags:declare-tag
         (setf cur-declare tag))
        (tags:package-nickname-tag
         (push tag cur-package-nickname-tags))
        (tags:package-use-tag
         (push tag cur-package-use-tags))
        (tags:expose-internal-function-tag
         (error-if-bad-expose-info-setup tag
                                         cur-name
                                         cur-lambda
                                         cur-declare
                                         cur-docstring)
         (let* ((packaged-function-name
                 (maybe-override-name
                  cur-namespace-tag
                  cur-name
                  (packaged-name cur-namespace-tag tag packages)
                  packages))
                (namespace (tags:namespace% cur-namespace-tag))
                (signature (tags:signature-text% tag))
                (signature-text (tags:signature-text% tag))
                (lambda-list (tags:maybe-lambda-list cur-lambda))
                (declare-form (tags:maybe-declare cur-declare))
                (docstring (tags:maybe-docstring cur-docstring)))
           (multiple-value-bind (function-name full-function-name simple-function)
               (extract-function-name-from-signature signature-text tag)
             (declare (ignore function-name))
             (pushnew (make-instance 'expose-internal-function
                                     :namespace% namespace
                                     :lisp-name% packaged-function-name
                                     :function-name% full-function-name
                                     :file% (tags:file% tag)
                                     :line% (tags:line% tag)
                                     :character-offset% (tags:character-offset% tag)
                                     :lambda-list% lambda-list
                                     :declare% declare-form
                                     :docstring% docstring
                                     :provide-declaration% simple-function
                                     :signature% signature)
                      functions
                      :test #'string=
                      :key #'lisp-name% ))
           (setf cur-lambda nil
                 cur-declare nil
                 cur-docstring nil
                 cur-name nil)))
        (tags:expose-external-function-tag
         (error-if-bad-expose-info-setup tag cur-name cur-lambda cur-declare cur-docstring)
         (let* ((packaged-function-name
                 (maybe-override-name
                  cur-namespace-tag
                  cur-name
                  (packaged-name cur-namespace-tag tag packages)
                  packages))
                (namespace (tags:namespace% cur-namespace-tag))
                (pointer (tags:pointer% tag))
                (function-name (extract-function-name-from-pointer pointer tag))
                (lambda-list (tags:maybe-lambda-list cur-lambda))
                (declare-form (tags:maybe-declare cur-declare))
                (docstring (tags:maybe-docstring cur-docstring)))
           (pushnew (make-instance 'expose-external-function
                                   :namespace% namespace
                                   :lisp-name% packaged-function-name
                                   :function-name% function-name
                                   :file% (tags:file% tag)
                                   :line% (tags:line% tag)
                                   :character-offset% (tags:character-offset% tag)
                                   :lambda-list% lambda-list
                                   :declare% declare-form
                                   :docstring% docstring
                                   :pointer% pointer)
                    functions
                    :test #'string=
                    :key #'lisp-name% )
           (setf cur-lambda nil
                 cur-declare nil
                 cur-docstring nil
                 cur-name nil)))
        (tags:expose-internal-method-tag
         (error-if-bad-expose-info-setup tag cur-name cur-lambda cur-declare cur-docstring)
         (multiple-value-bind (tag-class-name method-name)
             (cscrape:extract-method-name-from-signature (tags:signature-text% tag))
           (let* ((class-name (if tag-class-name
                                  tag-class-name
                                  (tags:name% cur-class)))
                  (class-key (make-class-key cur-namespace-tag class-name))
                  (class (gethash class-key classes))
                  (packaged-method-name (maybe-override-name
                                         cur-namespace-tag
                                         cur-name
                                         (packaged-name cur-namespace-tag method-name packages)
                                         packages))
                  (lambda-list (tags:maybe-lambda-list cur-lambda))
                  (declare-form (tags:maybe-declare cur-declare))
                  (docstring (tags:maybe-docstring cur-docstring)))
             (unless class (error "Couldn't find class ~a" class-key))
             (pushnew (make-instance 'expose-internal-method
                                     :class% class
                                     :lisp-name% packaged-method-name
                                     :method-name% method-name
                                     :file% (tags:file% tag)
                                     :line% (tags:line% tag)
                                     :character-offset% (tags:character-offset% tag)
                                     :lambda-list% lambda-list
                                     :declare% declare-form
                                     :docstring% docstring)
                      (methods% class)
                      :test #'string=
                      :key #'lisp-name%)))
         (setf cur-lambda nil
               cur-declare nil
               cur-docstring nil
               cur-name nil))
        (tags:expose-external-method-tag
         (error-if-bad-expose-info-setup tag cur-name cur-lambda cur-declare cur-docstring)
         (let* ((method-name (extract-method-name-from-pointer (tags:pointer% tag) tag))
                (class-name (tags:class-name% tag))
                (class-key (make-class-key cur-namespace-tag class-name))
                (class (gethash class-key classes))
                (packaged-method-name
                 (maybe-override-name
                  cur-namespace-tag
                  cur-name
                  (packaged-name cur-namespace-tag method-name packages)
                  packages))
                (lambda-list (tags:maybe-lambda-list cur-lambda))
                (declare-form (tags:maybe-declare cur-declare))
                (docstring (tags:maybe-docstring cur-docstring))
                (pointer (tags:pointer% tag)))
           (unless class (error "Couldn't find class ~a" class-key))
           (pushnew (make-instance 'expose-external-method
                                   :class% class
                                   :lisp-name% packaged-method-name
                                   :method-name% method-name
                                   :file% (tags:file% tag)
                                   :line% (tags:line% tag)
                                   :character-offset% (tags:character-offset% tag)
                                   :lambda-list% lambda-list
                                   :declare% declare-form
                                   :docstring% docstring
                                   :pointer% pointer)
                    (methods% class)
                    :test #'string=
                    :key #'lisp-name%)
           (setf cur-lambda nil
                 cur-declare nil
                 cur-docstring nil
                 cur-name nil)))
        (tags:lisp-internal-class-tag
         (when cur-docstring (error-if-bad-expose-info-setup* tag cur-docstring))
         (unless cur-namespace-tag (error 'missing-namespace :tag tag))
         (unless (string= (tags:namespace% cur-namespace-tag) (tags:namespace% tag))
           (error 'namespace-mismatch :tag tag))
         (setf cur-class tag)
         (let ((class-key (make-class-key cur-namespace-tag (tags:name% tag))))
           (unless (gethash class-key classes)
             (setf (gethash class-key classes)
                   (make-instance 'exposed-internal-class
                                  :file% (tags:file% tag)
                                  :line% (tags:line% tag)
                                  :package% (tags:package% tag)
                                  :character-offset% (tags:character-offset% tag)
                                  :meta-class% (tags:maybe-meta-class cur-namespace-tag cur-meta-class)
                                  :docstring% (tags:maybe-docstring cur-docstring)
                                  :base% (make-class-key cur-namespace-tag (tags:base% tag))
                                  :class-key% class-key
                                  :lisp-name% (lispify-class-name tag packages)
                                  :class-tag% tag
                                  :methods% nil))))
         (setf cur-docstring nil
               cur-meta-class nil))
        (tags:lisp-external-class-tag
         (when cur-docstring (error-if-bad-expose-info-setup* tag cur-docstring))
         (unless cur-namespace-tag (error 'missing-namespace :tag tag))
         (unless (string= (tags:namespace% cur-namespace-tag) (tags:namespace% tag))
           (error 'namespace-mismatch :tag tag))
         (setf cur-class tag)
         (let ((class-key (make-class-key cur-namespace-tag (tags:name% tag))))
           (unless (gethash class-key classes)
             (setf (gethash class-key classes)
                   (make-instance 'exposed-external-class
                                  :file% (tags:file% tag)
                                  :line% (tags:line% tag)
                                  :package% (tags:package% tag)
                                  :character-offset% (tags:character-offset% tag)
                                  :meta-class% (tags:maybe-meta-class cur-namespace-tag cur-meta-class)
                                  :docstring% (tags:maybe-docstring cur-docstring)
                                  :class-key% class-key
                                  :base% (make-class-key cur-namespace-tag (tags:base% tag))
                                  :lisp-name% (lispify-class-name tag packages)
                                  :class-tag% tag
                                  :methods% nil))))
         (setf cur-docstring nil
               cur-meta-class nil))
        (tags:begin-enum-tag
         (when cur-begin-enum
           (error 'tag-error
                  :message "Unexpected CL_BEGIN_ENUM - previous CL_BEGIN_ENUM at ~a:~d"
                  :message-args (list (file% cur-begin-enum) (line% cur-begin-enum))
                  :tag tag ))
         (setf cur-begin-enum (make-instance 'begin-enum
                                             :file% (tags:file% tag)
                                             :line% (tags:line% tag)
                                             :character-offset% (tags:character-offset% tag)
                                             :type% (tags:type% tag)
                                             :symbol% (maybe-namespace-symbol cur-namespace-tag (tags:symbol% tag))
                                             :description% (tags:description% tag))
               cur-values nil))
        (tags:value-enum-tag
         (push (make-instance 'value-enum
                              :file% (tags:file% tag)
                              :line% (tags:line% tag)
                              :character-offset% (tags:character-offset% tag)
                              :symbol% (maybe-namespace-symbol cur-namespace-tag (tags:symbol% tag))
                              :value% (tags:value% tag))
               cur-values))
        (tags:end-enum-tag
         (let ((end-symbol (maybe-namespace-symbol cur-namespace-tag (tags:symbol% tag))))
           (unless cur-begin-enum
             (error 'tag-error :message "Missing BEGIN_ENUM" :tag tag))
           (unless cur-values
             (error 'tag-error :message "Missing VALUES" :tag tag))
           (unless (string= (symbol% cur-begin-enum) end-symbol)
             (error 'tag-error
                    :message "Mismatch between symbols of CL_BEGIN_ENUM ~a and CL_END_ENUM ~a"
                    :message-args (list (symbol% cur-begin-enum) end-symbol)
                    :tag tag))
           (pushnew (make-instance 'completed-enum
                                   :begin-enum% cur-begin-enum
                                   :values% cur-values)
                    enums
                    :test #'string=
                    :key (lambda (x) (symbol% (begin-enum% x))))
           (setf cur-begin-enum nil
                 cur-values nil)))
        (tags:symbol-tag
         (let* ((c++-name (if (tags:c++-name% tag)
                              (tags:c++-name% tag)
                              (tags:lisp-name% tag)))
                (namespace (if (tags:namespace% tag)
                               (tags:namespace% tag)
                               (tags:namespace% (gethash (tags:package% tag) package-to-assoc))))
                (package (if (tags:package% tag)
                             (tags:package% tag)
                             (tags:package% (gethash (tags:namespace% tag) namespace-to-assoc))))
                (lisp-name (tags:lisp-name% tag))
                (exported (typep tag 'tags:symbol-external-tag))
                (shadow (typep tag 'tags:symbol-shadow-external-tag))
                (symbol (make-instance 'expose-symbol
                                       :lisp-name% lisp-name
                                       :c++-name% c++-name
                                       :namespace% namespace
                                       :package% package
                                       :package-str% (gethash package packages)
                                       :exported% exported
                                       :shadow% shadow)))
           (check-symbol-against-previous symbol previous-symbols)
           (push symbol symbols)))))
    (values (order-packages-by-use packages-to-create) functions symbols classes enums)))
                                                                                         
                                                                                         
