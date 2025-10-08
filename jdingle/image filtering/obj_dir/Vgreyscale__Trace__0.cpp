// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals
#include "verilated_vcd_c.h"
#include "Vgreyscale__Syms.h"


void Vgreyscale___024root__trace_chg_0_sub_0(Vgreyscale___024root* vlSelf, VerilatedVcd::Buffer* bufp);

void Vgreyscale___024root__trace_chg_0(void* voidSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root__trace_chg_0\n"); );
    // Init
    Vgreyscale___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vgreyscale___024root*>(voidSelf);
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    // Body
    Vgreyscale___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void Vgreyscale___024root__trace_chg_0_sub_0(Vgreyscale___024root* vlSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root__trace_chg_0_sub_0\n"); );
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Init
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 1);
    // Body
    bufp->chgBit(oldp+0,(vlSelfRef.clk));
    bufp->chgBit(oldp+1,(vlSelfRef.rst_n));
    bufp->chgBit(oldp+2,(vlSelfRef.in_valid));
    bufp->chgIData(oldp+3,(vlSelfRef.pixel_in),24);
    bufp->chgBit(oldp+4,(vlSelfRef.out_valid));
    bufp->chgCData(oldp+5,(vlSelfRef.gray_out),8);
    bufp->chgCData(oldp+6,((0xffU & (vlSelfRef.pixel_in 
                                     >> 0x10U))),8);
    bufp->chgCData(oldp+7,((0xffU & (vlSelfRef.pixel_in 
                                     >> 8U))),8);
    bufp->chgCData(oldp+8,((0xffU & vlSelfRef.pixel_in)),8);
    bufp->chgIData(oldp+9,(vlSelfRef.grayscale__DOT__acc),18);
}

void Vgreyscale___024root__trace_cleanup(void* voidSelf, VerilatedVcd* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vgreyscale___024root__trace_cleanup\n"); );
    // Init
    Vgreyscale___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vgreyscale___024root*>(voidSelf);
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VlUnpacked<CData/*0:0*/, 1> __Vm_traceActivity;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        __Vm_traceActivity[__Vi0] = 0;
    }
    // Body
    vlSymsp->__Vm_activity = false;
    __Vm_traceActivity[0U] = 0U;
}
