; Copyright lowRISC contributors.
; Licensed under the Apache License, Version 2.0, see LICENSE for details.
; SPDX-License-Identifier: Apache-2.0
;
; Multiplier lemma T2 (integer arithmetic, expect `unsat`).
;
; With m1..m4 the exact products computed by md_ref_pkg::rtl_mul_mac1 / rtl_mul_hi_from, the wide
; model of mul_t1.smt2 equals the Sail result md_ref_pkg::spec_mul_wide, and the side conditions
; assumed by mul_t1.smt2 hold. Together, T1 and T2 show for all a, b and signed_mode:
;
;   rtl_mul_lo(a, b)         == spec_mul_wide(0, 0, a, b)[31:0]                       (MUL)
;   rtl_mul_hi(sm, a, b)     == spec_mul_wide(sm[0], sm[1], a, b)[63:32]              (MULH*)
;
; which is the arithmetic step SAT solvers cannot do (distributivity of multiplication).
;
; Integer reading of the bit-vector values:
;   a = ah*2^16 + al, b = bh*2^16 + bl with al, ah, bl, bh in [0, 2^16)
;   a[31] = ah div 2^15,   sign_a = signed_mode[0] & a[31],   sign_b = signed_mode[1] & b[31]
;   $signed({s, h}) for a 17-bit operand = h - s*2^16
;   A 17x17 signed product assigned to a 34-bit signed variable is exact iff it lies in
;   [-2^33, 2^33), which is checked below.
;   Sail: rs1_int = signed_rs1 ? signed(a) : unsigned(a); signed(a) = a - a[31]*2^32;
;         spec_mul_wide = (rs1_int * rs2_int) mod 2^64 (the 256-bit product truncated to 64 bits).

(set-logic QF_NIA)
(declare-const al Int)
(declare-const ah Int)
(declare-const bl Int)
(declare-const bh Int)
(declare-const sm0 Int)
(declare-const sm1 Int)
(define-fun r16 ((v Int)) Bool (and (<= 0 v) (< v 65536)))
(assert (and (r16 al) (r16 ah) (r16 bl) (r16 bh)
             (or (= sm0 0) (= sm0 1)) (or (= sm1 0) (= sm1 1))))

(define-fun a31 () Int (div ah 32768))
(define-fun b31 () Int (div bh 32768))
(define-fun sign_a () Int (* sm0 a31))
(define-fun sign_b () Int (* sm1 b31))

; 17-bit signed multiplier operands
(define-fun Al () Int al)                           ; $signed({1'b0, a[15:0]})
(define-fun Bl () Int bl)                           ; $signed({1'b0, b[15:0]})
(define-fun Ah () Int (- ah (* sign_a 65536)))      ; $signed({sign_a, a[31:16]})
(define-fun Bh () Int (- bh (* sign_b 65536)))      ; $signed({sign_b, b[31:16]})

; Exact products
(define-fun M1 () Int (* Al Bl))
(define-fun M2 () Int (* Al Bh))
(define-fun M3 () Int (* Ah Bl))
(define-fun M4 () Int (* Ah Bh))
(define-fun fits34 ((v Int)) Bool (and (<= (- 8589934592) v) (< v 8589934592)))

; Wide model of mul_t1.smt2
(define-fun X () Int (+ (div M1 65536) M2 M3))
(define-fun lo_w () Int (+ (* (mod X 65536) 65536) (mod M1 65536)))
(define-fun hi_w () Int (mod (+ M4 (div X 65536)) 4294967296))

; Sail
(define-fun ua () Int (+ (* ah 65536) al))
(define-fun ub () Int (+ (* bh 65536) bl))
(define-fun A () Int (ite (= sm0 1) (- ua (* a31 4294967296)) ua))
(define-fun B () Int (ite (= sm1 1) (- ub (* b31 4294967296)) ub))
(define-fun P () Int (mod (* A B) 18446744073709551616))

(define-fun side_conditions () Bool
  (and (fits34 M1) (fits34 M2) (fits34 M3) (fits34 M4)
       (<= 0 M1) (< M1 4294967296)
       (<= (- 8589934592) X) (< X 8589934592)
       (=> (and (= sm0 0) (= sm1 0)) (<= 0 X))))

(assert (not (and side_conditions
                  (= lo_w (mod P 4294967296))
                  (= hi_w (div P 4294967296)))))
(check-sat)
