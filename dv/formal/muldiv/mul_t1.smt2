; Copyright lowRISC contributors.
; Licensed under the Apache License, Version 2.0, see LICENSE for details.
; SPDX-License-Identifier: Apache-2.0
;
; Multiplier lemma T1 (bit level, expect `unsat`).
;
; The plumbing of md_ref_pkg::rtl_mul_lo / rtl_mul_hi (which mirrors the RV32MSingleCycle datapath
; of ibex_multdiv_fast) agrees with a wide, non-wrapping model of the same computation, for ANY
; values of the four 17x17 products m1..m4, provided the side conditions hold. T2 (mul_t2.smt2)
; shows that the side conditions hold for the actual products, and that the wide model equals the
; Sail result. Because the products are free here, this query contains no multipliers and is
; easy for a SAT based solver.
;
; Correspondence with md_ref_pkg:
;   m1 = al*bl, m2 = al*Bh, m3 = Ah*bl (rtl_mul_mac1), m4 = Ah*Bh (rtl_mul_hi_from), all 34-bit
;   signed; sm = signed_mode.
; Correspondence of the wide model with the integer model in mul_t2.smt2 (no wrapping occurs in
; 80 bits, since every |value| < 2^70):
;   bvashr x 16 = (div x 65536)   x[15:0] = (mod x 65536)   x[31:0] = (mod x 2^32)

(set-logic QF_BV)
(declare-const sm (_ BitVec 2))
(declare-const m1 (_ BitVec 34))
(declare-const m2 (_ BitVec 34))
(declare-const m3 (_ BitVec 34))
(declare-const m4 (_ BitVec 34))
(define-fun signed_mult () Bool (not (= sm #b00)))

; ---- RTL-shaped datapath (md_ref_pkg) ----
; rtl_mul_mac1: s1 = {18'h0, m1[31:16]}; mac1 = s1 + m2 + m3   (34-bit)
(define-fun summand1 () (_ BitVec 34) (concat #b000000000000000000 ((_ extract 31 16) m1)))
(define-fun mac1 () (_ BitVec 34) (bvadd (bvadd summand1 m2) m3))
; rtl_mul_lo: {mac1[15:0], m1[15:0]}
(define-fun lo_rtl () (_ BitVec 32) (concat ((_ extract 15 0) mac1) ((_ extract 15 0) m1)))
; rtl_mul_hi_from: accum = {16{signed_mult & mac1[33]}, mac1[33:16]}; (accum + m4)[31:0]
(define-fun accum () (_ BitVec 34)
  (concat (ite (and signed_mult (= ((_ extract 33 33) mac1) #b1)) #xffff #x0000)
          ((_ extract 33 16) mac1)))
(define-fun hi_rtl () (_ BitVec 32) ((_ extract 31 0) (bvadd accum m4)))

; ---- Wide model ----
(define-fun W1 () (_ BitVec 80) ((_ sign_extend 46) m1))
(define-fun W2 () (_ BitVec 80) ((_ sign_extend 46) m2))
(define-fun W3 () (_ BitVec 80) ((_ sign_extend 46) m3))
(define-fun W4 () (_ BitVec 80) ((_ sign_extend 46) m4))
(define-fun X () (_ BitVec 80) (bvadd (bvadd (bvashr W1 (_ bv16 80)) W2) W3))
(define-fun lo_w () (_ BitVec 32) (concat ((_ extract 15 0) X) ((_ extract 15 0) W1)))
(define-fun hi_w () (_ BitVec 32) ((_ extract 31 0) (bvadd W4 (bvashr X (_ bv16 80)))))

; ---- Side conditions (proved in mul_t2.smt2) ----
(assert (bvsge W1 (_ bv0 80)))
(assert (bvslt W1 (bvshl (_ bv1 80) (_ bv32 80))))
(assert (bvsge X (bvneg (bvshl (_ bv1 80) (_ bv33 80)))))
(assert (bvslt X (bvshl (_ bv1 80) (_ bv33 80))))
(assert (=> (not signed_mult) (bvsge X (_ bv0 80))))

(assert (not (and (= lo_rtl lo_w) (= hi_rtl hi_w))))
(check-sat)
