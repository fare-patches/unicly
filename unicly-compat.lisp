;;; :FILE-CREATED <Timestamp: #{2011-04-22T17:53:30-04:00Z}#{11165} - by MON>
;;; :FILE unicly/unicly-v1-compat.lisp
;;; ==============================

;; ,----
;; | Universally administered and locally administered addresses are distinguished by
;; | setting the second least significant bit of the most significant byte of the
;; | address. If the bit is 0, the address is universally administered. If it is 1,
;; | the address is locally administered.
;; `----
;;
;; ,----
;; | The lowest addressed octet (octet number 10) contains the global/local bit and
;; | the unicast/multicast bit, and is the first octet of the address transmitted on
;; | an 802.3 LAN.
;; `----
;;
;; ,---- RFC4122 Section 4.5 "Node IDs that Do Not Identify the Host"
;; | This section describes how to generate a version 1 UUID if an IEEE
;; | 802 address is not available, or its use is not desired.
;; |
;; | A better solution is to obtain a 47-bit cryptographic quality random
;; | number and use it as the low 47 bits of the node ID, with the least
;; | significant bit of the first octet of the node ID set to one.  This
;; | bit is the unicast/multicast bit, which will never be set in IEEE 802
;; | addresses obtained from network cards.  Hence, there can never be a
;; | conflict between UUIDs generated by machines with and without network
;; | cards.  (Recall that the IEEE 802 spec talks about transmission
;; | order, which is the opposite of the in-memory representation that is
;; | discussed in this document.)
;; | 
;; | For compatibility with earlier specifications, note that this
;; | document uses the unicast/multicast bit, instead of the arguably more
;; | correct local/global bit.
;; `----

;;; ==============================
;; ieee-802-2001 page 24 Section 9.5.2 illustrative examples:
;;
;; For the examples, the bit significance of an OUI in general is defined to be as
;; in Figure 10.
;;         MSB             LSB
;;          ----------------
;; Octet 0 | h g f e d c b a
;; Octet 1 | p o n m l k j i
;; Octet 2 | x w v u t s r q
;;          ----------------
;;
;; Figure 10--Bit significance of an OUI
;;
;; When used in LAN MAC addresses:
;; Bit "a" of the OUI = I/G address bit. ;; Individual/Group bit AKA unicast/multicast
;; Bit "b" of the OUI = U/L address bit. ;; Universally or Locally administered bit
;;
;; When used in protocol identifiers:
;; Bit "a" of the OUI = M bit.
;; Bit "b" of the OUI (always zero) = X bit.
;;
;;; ==============================

;;; ==============================

(in-package #:unicly)
;; *package*

(defvar *clock-seq-uuid* 0)

(defvar *node-uuid* nil)

;;; ==============================
;; :NOTE It isn't clear whether *ticks-per-count-uuid* can or should be set to
;; `cl:internal-time-units-per-second'
;; As of 2011-04-23: 
;; On SBCL 1.0.47.1 this value is 1000
;; On GNU CLISP 2.48 (2009-07-28) it is 1,000,000.
;; We set this to 1024 to allow declarations in `get-timestamp-uuid'
(defvar *ticks-per-count-uuid* 1024)



;;; ==============================
;; :NOTE As of 2011-04-23 uuid:get-node-id has a(nother) bug in that it sets bit
;; 0 of the the LSByte of a 48bit integer with:
;;
;; (setf node (dpb #b01 (byte 8 0) (random #xffffffffffff *random-state-uuid*)))
;;
;; IEEE-802 MAC addresses are transfered on the wire in bit-reverse notation
;; with the least significant bit of each _octet_ first the MSByte is still Octet 0 
;; not of the entire 48bit integer.
;;
;; The MAC address 12:34:56:78:9A:BC is be transmitted over the wire with 
;; MSByte first and the bits of each octet in LSBit -> MSBit form:
;;
;; MSByte                                                     LSByte
;;        BYTE-5   BYTE-4   BYTE-3   BYTE-2   BYTE-1   BYTE-0
;;       OCTET-0  OCTET-1  OCTET-2  OCTET-3  OCTET-4  OCTET-5
;;      01001000 00101100 01101010 00011110 01011001 00111101
;;
;;                                       msbit.       lsbit.
;;                                            |            | 
;; #x12  18 ;; => 18 (5 bits, #x12, #o22,   #b00010010) -> 01001000 
;; #x34  52 ;; => 52 (6 bits, #x34, #o64,   #b00110100) -> 00101100
;; #x56  86 ;; => 86 (7 bits, #x56, #o126,  #b01010110) -> 01101010 
;; #x78 120 ;; => 120 (7 bits, #x78, #o170, #b01111000) -> 00011110
;; #x9A 154 ;; => 154 (8 bits, #x9A, #o232, #b10011010) -> 01011001
;; #xBC 188 ;; => 188 (8 bits, #xBC, #o274, #b10111100) -> 00111101

(defun get-node-id ()
  ;; Don't bother getting the MAC address of an ethernet device. 
  ;; RFC4122 Secion 5 says it is perfectly feasible to just use a random number.
  (declare (optimize (speed 3)))
  (let* ((*random-state* *random-state-uuid*)
         (rand-node (the uuid-ub48 (random #xffffffffffff))))
    (declare (uuid-ub48 rand-node))
    (the uuid-ub48 (dpb #b01 (byte 1 40) rand-node))))

;; :NOTE closed over value uuids-this-tick should not exceed `unicly::*ticks-per-count-uuid*'.
(let ((uuids-this-tick 0) 
      (last-time 0))
  (defun get-timestamp-uuid ()
    ;; :NOTE Can't declare if we use value of
    ;; `cl:internal-time-units-per-second' in
    ;; `unicly::*ticks-per-count-uuid*'.
    (declare ((mod 1025) *ticks-per-count-uuid* uuids-this-tick))
    (tagbody 
     restart
       ;; Supposedly 10010304000 is time between 1582-10-15 and 1900-01-01 in seconds
       ;; 100 nano-seconds => (/ (expt 10 9) 100) => 10000000
       ;; (* 10010304000 (/ (expt 10 9) 100)) => 100103040000000000
       (let ((time-now 
              #-sbcl(+ (* (get-universal-time) 10000000) 100103040000000000)
              #+sbcl(+ (* 
                        (+ (sb-ext:get-time-of-day) sb-impl::unix-to-universal-time)
                        10000000)
                       100103040000000000)))
         (if (and (/= last-time time-now)
                  (setf uuids-this-tick 0 
                        last-time time-now))
             (return-from get-timestamp-uuid time-now)
    
             (if (and (< uuids-this-tick *ticks-per-count-uuid*)
                      (incf uuids-this-tick))
                 (return-from get-timestamp-uuid (+ time-now uuids-this-tick))
                 (or (sleep 0.0001)
                     (go restart))))))))

(defun make-v1-uuid ()
  (let ((timestamp (get-timestamp-uuid)))
    (declare ((unsigned-byte 60)  timestamp)
             ((unsigned-byte 48)  *node-uuid*)
             ((unsigned-byte 48)  *node-uuid*))
    (make-instance 'uuid
		   :time-low (ldb (byte 32 0) timestamp)
		   :time-mid (ldb (byte 16 32) timestamp)
		   :time-high (dpb #b0001 (byte 4 12) (ldb (byte 12 48) timestamp))
		   :clock-seq-var (dpb #b10 (byte 2 6) (ldb (byte 6 8) *clock-seq-uuid*))
		   :clock-seq-low (ldb (byte 8 0) *clock-seq-uuid*) 
		   :node *node-uuid*)))

(eval-when (:load-toplevel :execute)
  (when (zerop *clock-seq-uuid*) 
    (setf *clock-seq-uuid* (random 10000 *random-state-uuid*)))

  (unless *node-uuid* (setf *node-uuid* (get-node-id))))
   

;;; ==============================
;;; :DOCUMENTATION
;;; ==============================

(vardoc  '*clock-seq-uuid*
"A clock sequence for use with `unicly:make-v1-uuid'.~%~@
Intial value is 0 at beginning of current session.~%~@
At loadtime it is set to a `cl:random' integer value using
`unicly::*random-state-uuid*' as the random-state.~%~@
Thereafter its value remains unchanged fur the duration of the session.~%~@
:EXAMPLE~%~@
 { ... <EXAMPLE> ... } ~%~@
:SEE-ALSO `*ticks-per-count-uuid*', `make-v1-uuid'.~%►►►")

(vardoc '*node-uuid*
"A random number of type `uuid-ub48'.~%~@
Per RFC4122 Section 4.5 \"Node IDs that Do Not Identify the Host\" the bit at
index 40 is set to 1.
The 40 bit corresponds to a unicast/multicast bit which is referenced by
IEEE-802-2001 as the Individual/Group or I/G bit. It occurs in the least
significant bit of octet-0/byte-5 (MSB byte) of MAC address. Because this bit
will never be set in IEEE 802 addresses obtained from network cards. we can
reasonably enusre that a version 1 UUID will not conflict with other v1 UUIDs
generated by machines which take their node value from the MAC address of their
hardware network cards.
:EXAMPLE~%~@
 { ... <EXAMPLE> ... } ~%~@
:SEE-ALSO `<XREF>'.~%►►►")

(vardoc '*ticks-per-count-uuid*
"The number of version 1 UUIDS that can be generated in a given time interval.~%~@
The function `unicly::get-timestamp-uuid' compares this value with the current
closed over value of uuids-this-tick when generating timestampsfor
`unicly:make-v1-uuid'.~%~@
:NOTE Common Lisp provides `cl:internal-time-units-per-second' which returns a
postive integer representing the number of internal time units in one second but
this value is implementation-dependent. As of 2011-04-23 on SBCL 1.0.47.1 this
value is 1000, whereas on GNU CLISP 2.48 (2009-07-28) it is 1,000,000.~%~@
:SEE \(info \"\(ansicl\)nternal-time-units-per-second\"\)
:SEE :FILE sbcl/src/code/early-time.lisp
:SEE :FILE sbcl/src/code/unix.lisp
:EXAMPLE~%~@
 { ... <EXAMPLE> ... } ~%~@
:SEE-ALSO `unicly::*clock-seq-uuid*',
`sb-unix::micro-seconds-per-internal-time-unit', .~%►►►")

;; (eq sb-impl::*default-external-format* :UTF-8)


;;; ==============================
;;; :FUNCTIONS
;;; ==============================

(fundoc 'make-v1-uuid
"Return a time based version 1 UUID.~%~@
RFC4122 Section ????
:NOTE This function does not rely on \(or query\) the value of the system's
hardware MAC address \(e.g. an ethernet device\). Although, RFC4122 describes a process 
Section 5 says it is perfectly feasible to just use a 48 bit random number as the node value.
Therefor, we set the %uuid_node slot of class instances of
`unicly:unique-universal-identifier' to the value of the special variable
`unicly::*node-uuid*' which is set once per session at loadtime to the return
value of `unicly::get-node-id'.~%~@
:EXAMPLE~%~@
 { ... <EXAMPLE> ... } ~%~@
:SEE-ALSO `make-v3-uuid', `make-v5-uuid', `make-v1-uuid', `make-null-uuid'.~%►►►")

#+nil
(fundoc 'uuid-get-bytes ; ######
            "Convert UUID-STRING to a string of characters.~%~@
UUID-STRING is a is a string as returned by `uuid-print-bytes'.~%~@
Return value is constructed from the `cl:code-char' of each number in UUID-STRING.~%~@
Return value has is of type `uuid-byte-string' with the type signature:~%
 \(simple-array character \(16\)\)~%~@
And will satisfy the predicate `uuid-byte-string-p'.~%~@
Helper function for `make-v3-uuid' and `make-v5-uuid'.~%~@
:EXAMPLE~%
 \(uuid-get-bytes 
  \(uuid-print-bytes nil \(make-uuid-from-string \"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"\)\)\)~%
\(uuid-get-bytes \"5E320838715730398383652D96705A7D\"\)~%~@
:SEE-ALSO `<XREF>'.~%►►►")

#+nil
(fundoc '%uuid-get-bytes-if ; ######
"Helper function for `uuid-get-bytes'.~%~@
Verify that arg CHK-UUID-STR is of type `uuid-hex-string-32'.~%~@
Signal an error if not.~%~@
:EXAMPLE~%~@
 \(%uuid-get-bytes-if \"6ba7b8109dad11d180b400c04fd430c8\"\)~%
 \(%uuid-get-bytes-if \"6BA7B8109DAD11D180B400C04FD430C8\"\)~%
 \(%uuid-get-bytes-if \"6ba7b8109dad11d180b400c04fd430c8-Q\"\)~%~@
:SEE-ALSO `uuid-hex-string-32-p'.~%►►►")

#+nil
(fundoc 'uuid-load-bytes ; ######
 "Helper function.~%~@
Load as if by `cl:dpb' the bytes of BYTE-ARRAY.~%~@
Return bytes set as integer values.~%~@
keyword BYTE-SIZE is a byte width to set. Default is 8.~%~@
keyword START is the position in BYTE-ARRAY to begin setting bytes from. Default is 0.~%~@
END is the position to stop setting bytes.~%~@
:EXAMPLE~%~@
 { ... <EXAMPLE> ... } ~%~@
:SEE-ALSO `<XREF>'.~%►►►")

#+nil
(fundoc 'uuid-to-byte-array ; ######
  "Convert UUID to a byte-array.~%~@
Arg UUID should be an instance of the UNIQUE-UNIVERSAL-IDENTIFIER class.~%~@
Return value is an array of type `uuid-byte-array-16' with the type signature:~%
 \(simple-array \(unsigned-byte 8\) \(16\)\)~%~@
It will satisfy the predicate `uuid-byte-array-16-p'.
:EXAMPLE~%~@
 \(uuid-to-byte-array *uuid-namespace-dns*\)~%~@
:SEE-ALSO `uuid-from-byte-array'.~%►►►")

;;; ==============================


;; Local Variables:
;; indent-tabs-mode: nil
;; show-trailing-whitespace: t
;; mode: lisp-interaction
;; package: unicly
;; End:

;;; ==============================
;;; EOF
