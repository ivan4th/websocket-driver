(in-package :cl-user)
(defpackage websocket-driver
  (:nicknames :wsd)
  (:use :cl
        :cl-reexport)
  (:import-from :websocket-driver.driver.hybi
                :hybi)
  (:import-from :websocket-driver.driver.client
                :client)
  (:import-from :websocket-driver.util
                :with-package-functions)
  (:import-from :alexandria
                :delete-from-plist))
(in-package :websocket-driver)

(syntax:use-syntax :annot)

@export
(defun make-client (url &optional protocols &rest options)
  (apply #'make-instance 'client
         :url url
         :masking t
         :protocols protocols
         options))

@export
(defun make-server-for-clack (env &rest options &key socket &allow-other-keys)
  (apply #'make-instance 'hybi
         :socket (or socket
                     (getf env :clack.io))
         :env env
         :require-masking t
         options))

@export
(defun make-server-for-wookie (req &rest options &key socket &allow-other-keys)
  (with-package-functions :wookie (request-headers
                                   request-socket
                                   request-method)
    (let* ((headers (let ((table (make-hash-table :test #'equal)))
                      (alexandria:doplist (k v (if (hash-table-p (request-headers req))
                                                   (alexandria:hash-table-plist (request-headers req))
                                                   (request-headers req))
                                             table)
                                          (setf (gethash (string-downcase k) table) v))))
           (env #.`(list
                    ,@(mapcan (lambda (name)
                                (list (intern (format nil "HTTP-~A" name) :keyword)
                                      `(gethash ,(string-downcase name) headers)))
                              (list :connection
                                    :host
                                    :origin
                                    :sec-websocket-key
                                    :sec-websocket-version
                                    :upgrade))
                    :headers headers
                    :request-method (request-method req))))
      (apply #'make-server-for-clack
             env
             :socket (or socket
                         (request-socket req))
             options))))

@export
(defun make-server (env &optional protocols &rest options)
  (check-type protocols list)
  (let ((type (or (getf options :type)
                  :clack)))
    (apply (ecase type
             (:clack  #'make-server-for-clack)
             (:wookie #'make-server-for-wookie))
           env
           :protocols protocols
           (delete-from-plist options :type))))

@export
(defun websocket-p (env &key (type :clack))
  (flet ((clack-websocket-p (env)
           (let ((headers (getf env :headers)))
             (and (eq (getf env :request-method) :get)
                  (ppcre:scan "(?i)(?:^|\\s|,)upgrade(?:$|\\s|,)" (gethash "connection" headers ""))
                  (string-equal (gethash "upgrade" headers) "websocket"))))
         (wookie-websocket-p (req)
           (with-package-functions :wookie (request-method
                                            request-headers)
             (unless (eq (request-method req) :get)
               (return-from websocket-p nil))

             (let* ((headers (request-headers req))
                    (connection (getf headers :connection))
                    (upgrade (getf headers :upgrade)))
               (and connection
                    upgrade
                    (ppcre:scan "(?i)(?:^|\\s|,)upgrade(?:$|\\s|,)" connection)
                    (string-equal upgrade "websocket"))))))
    (funcall (ecase type
               (:clack  #'clack-websocket-p)
               (:wookie #'wookie-websocket-p))
             env)))

(reexport-from :websocket-driver.driver.base
               :include '(:driver
                          :ready-state
                          :set-header
                          :start-connection
                          :version
                          :protocol
                          :parse
                          :send
                          :send-text
                          :send-binary
                          :send-ping
                          :close-connection))

(reexport-from :event-emitter
               :include '(:listeners
                          :listener-count
                          :add-listener
                          :on
                          :once
                          :remove-listener
                          :remove-all-listeners
                          :emit))

(reexport-from :websocket-driver.error
               :include '(:protocol-error))

(reexport-from :websocket-driver.events
               :include '(:event
                          :connect-event
                          :open-event
                          :message-event
                          :event-data
                          :close-event
                          :event-code
                          :event-reason))
