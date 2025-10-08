// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vgreyscale.h for the primary calling header

#ifndef VERILATED_VGREYSCALE___024ROOT_H_
#define VERILATED_VGREYSCALE___024ROOT_H_  // guard

#include "verilated.h"


class Vgreyscale__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vgreyscale___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(rst_n,0,0);
    VL_IN8(in_valid,0,0);
    VL_OUT8(out_valid,0,0);
    VL_OUT8(gray_out,7,0);
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__rst_n__0;
    CData/*0:0*/ __VactContinue;
    VL_IN(pixel_in,23,0);
    IData/*17:0*/ grayscale__DOT__acc;
    IData/*31:0*/ __VactIterCount;
    VlTriggerVec<2> __VactTriggered;
    VlTriggerVec<2> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vgreyscale__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vgreyscale___024root(Vgreyscale__Syms* symsp, const char* v__name);
    ~Vgreyscale___024root();
    VL_UNCOPYABLE(Vgreyscale___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
