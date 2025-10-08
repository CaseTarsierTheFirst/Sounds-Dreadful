// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vgreyscale.h for the primary calling header

#include "Vgreyscale__pch.h"
#include "Vgreyscale___024root.h"

VL_ATTR_COLD void Vgreyscale___024root___eval_static(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_static\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
}

VL_ATTR_COLD void Vgreyscale___024root___eval_initial(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_initial\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vgreyscale___024root___eval_final(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_final\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vgreyscale___024root___eval_settle(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___eval_settle\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vgreyscale___024root___dump_triggers__act(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___dump_triggers__act\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VactTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge clk)\n");
    }
    if ((2ULL & vlSelfRef.__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @(negedge rst_n)\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vgreyscale___024root___dump_triggers__nba(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___dump_triggers__nba\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1U & (~ vlSelfRef.__VnbaTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge clk)\n");
    }
    if ((2ULL & vlSelfRef.__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @(negedge rst_n)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vgreyscale___024root___ctor_var_reset(Vgreyscale___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root___ctor_var_reset\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1638864771569018232ull);
    vlSelf->in_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2339549897027650563ull);
    vlSelf->pixel_in = VL_SCOPED_RAND_RESET_I(24, __VscopeHash, 18142457610945471946ull);
    vlSelf->out_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2886291494070200219ull);
    vlSelf->gray_out = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 2868972383873034794ull);
    vlSelf->grayscale__DOT__acc = VL_SCOPED_RAND_RESET_I(18, __VscopeHash, 18117074214580930127ull);
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9526919608049418986ull);
    vlSelf->__Vtrigprevexpr___TOP__rst_n__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14803524876191471008ull);
}
