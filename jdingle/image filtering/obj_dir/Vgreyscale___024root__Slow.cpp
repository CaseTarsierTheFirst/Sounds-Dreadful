// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vgreyscale.h for the primary calling header

#include "Vgreyscale__pch.h"
#include "Vgreyscale__Syms.h"
#include "Vgreyscale___024root.h"

void Vgreyscale___024root___ctor_var_reset(Vgreyscale___024root* vlSelf);

Vgreyscale___024root::Vgreyscale___024root(Vgreyscale__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vgreyscale___024root___ctor_var_reset(this);
}

void Vgreyscale___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vgreyscale___024root::~Vgreyscale___024root() {
}
