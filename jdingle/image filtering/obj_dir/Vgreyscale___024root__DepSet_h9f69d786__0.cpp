// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vgreyscale.h for the primary calling header

#include "Vgreyscale__pch.h"
#include "Vgreyscale___024root.h"

void Vgreyscale___024root___eval_act(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_act\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

void Vgreyscale___024root___nba_sequent__TOP__0(Vgreyscale___024root* vlSelf);

void Vgreyscale___024root___eval_nba(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_nba\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        Vgreyscale___024root___nba_sequent__TOP__0(vlSelf);
    }
}

VL_INLINE_OPT void Vgreyscale___024root___nba_sequent__TOP__0(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___nba_sequent__TOP__0\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.out_valid = ((IData)(vlSelfRef.rst_n) 
                           && (IData)(vlSelfRef.in_valid));
    if (vlSelfRef.rst_n) {
        if (vlSelfRef.in_valid) {
            vlSelfRef.gray_out = (0xffU & (((((IData)(0x4dU) 
                                              * (0xffU 
                                                 & (vlSelfRef.pixel_in 
                                                    >> 0x10U))) 
                                             + ((IData)(0x96U) 
                                                * (0xffU 
                                                   & (vlSelfRef.pixel_in 
                                                      >> 8U)))) 
                                            + ((IData)(0x1dU) 
                                               * (0xffU 
                                                  & vlSelfRef.pixel_in))) 
                                           >> 8U));
            vlSelfRef.grayscale__DOT__acc = (0x3ffffU 
                                             & ((((IData)(0x4dU) 
                                                  * 
                                                  (0xffU 
                                                   & (vlSelfRef.pixel_in 
                                                      >> 0x10U))) 
                                                 + 
                                                 ((IData)(0x96U) 
                                                  * 
                                                  (0xffU 
                                                   & (vlSelfRef.pixel_in 
                                                      >> 8U)))) 
                                                + ((IData)(0x1dU) 
                                                   * 
                                                   (0xffU 
                                                    & vlSelfRef.pixel_in))));
        }
    } else {
        vlSelfRef.gray_out = 0U;
        vlSelfRef.grayscale__DOT__acc = 0U;
    }
}

void Vgreyscale___024root___eval_triggers__act(Vgreyscale___024root* vlSelf);

bool Vgreyscale___024root___eval_phase__act(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_phase__act\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    VlTriggerVec<2> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vgreyscale___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelfRef.__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelfRef.__VactTriggered, vlSelfRef.__VnbaTriggered);
        vlSelfRef.__VnbaTriggered.thisOr(vlSelfRef.__VactTriggered);
        Vgreyscale___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vgreyscale___024root___eval_phase__nba(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_phase__nba\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelfRef.__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vgreyscale___024root___eval_nba(vlSelf);
        vlSelfRef.__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vgreyscale___024root___dump_triggers__nba(Vgreyscale___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vgreyscale___024root___dump_triggers__act(Vgreyscale___024root* vlSelf);
#endif  // VL_DEBUG

void Vgreyscale___024root___eval(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY(((0x64U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vgreyscale___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("greyscale.sv", 2, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelfRef.__VactIterCount = 0U;
        vlSelfRef.__VactContinue = 1U;
        while (vlSelfRef.__VactContinue) {
            if (VL_UNLIKELY(((0x64U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vgreyscale___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("greyscale.sv", 2, "", "Active region did not converge.");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
            vlSelfRef.__VactContinue = 0U;
            if (Vgreyscale___024root___eval_phase__act(vlSelf)) {
                vlSelfRef.__VactContinue = 1U;
            }
        }
        if (Vgreyscale___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vgreyscale___024root___eval_debug_assertions(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_debug_assertions\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");}
    if (VL_UNLIKELY(((vlSelfRef.rst_n & 0xfeU)))) {
        Verilated::overWidthError("rst_n");}
    if (VL_UNLIKELY(((vlSelfRef.in_valid & 0xfeU)))) {
        Verilated::overWidthError("in_valid");}
    if (VL_UNLIKELY(((vlSelfRef.pixel_in & 0xff000000U)))) {
        Verilated::overWidthError("pixel_in");}
}
#endif  // VL_DEBUG
