// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vgreyscale__pch.h"
#include "verilated_vcd_c.h"

//============================================================
// Constructors

Vgreyscale::Vgreyscale(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vgreyscale__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst_n{vlSymsp->TOP.rst_n}
    , in_valid{vlSymsp->TOP.in_valid}
    , out_valid{vlSymsp->TOP.out_valid}
    , gray_out{vlSymsp->TOP.gray_out}
    , pixel_in{vlSymsp->TOP.pixel_in}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
    contextp()->traceBaseModelCbAdd(
        [this](VerilatedTraceBaseC* tfp, int levels, int options) { traceBaseModel(tfp, levels, options); });
}

Vgreyscale::Vgreyscale(const char* _vcname__)
    : Vgreyscale(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vgreyscale::~Vgreyscale() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vgreyscale___024root___eval_debug_assertions(Vgreyscale___024root* vlSelf);
#endif  // VL_DEBUG
void Vgreyscale___024root___eval_static(Vgreyscale___024root* vlSelf);
void Vgreyscale___024root___eval_initial(Vgreyscale___024root* vlSelf);
void Vgreyscale___024root___eval_settle(Vgreyscale___024root* vlSelf);
void Vgreyscale___024root___eval(Vgreyscale___024root* vlSelf);

void Vgreyscale::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vgreyscale::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vgreyscale___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_activity = true;
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vgreyscale___024root___eval_static(&(vlSymsp->TOP));
        Vgreyscale___024root___eval_initial(&(vlSymsp->TOP));
        Vgreyscale___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vgreyscale___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vgreyscale::eventsPending() { return false; }

uint64_t Vgreyscale::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vgreyscale::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vgreyscale___024root___eval_final(Vgreyscale___024root* vlSelf);

VL_ATTR_COLD void Vgreyscale::final() {
    Vgreyscale___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vgreyscale::hierName() const { return vlSymsp->name(); }
const char* Vgreyscale::modelName() const { return "Vgreyscale"; }
unsigned Vgreyscale::threads() const { return 1; }
void Vgreyscale::prepareClone() const { contextp()->prepareClone(); }
void Vgreyscale::atClone() const {
    contextp()->threadPoolpOnClone();
}
std::unique_ptr<VerilatedTraceConfig> Vgreyscale::traceConfig() const {
    return std::unique_ptr<VerilatedTraceConfig>{new VerilatedTraceConfig{false, false, false}};
};

//============================================================
// Trace configuration

void Vgreyscale___024root__trace_decl_types(VerilatedVcd* tracep);

void Vgreyscale___024root__trace_init_top(Vgreyscale___024root* vlSelf, VerilatedVcd* tracep);

VL_ATTR_COLD static void trace_init(void* voidSelf, VerilatedVcd* tracep, uint32_t code) {
    // Callback from tracep->open()
    Vgreyscale___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vgreyscale___024root*>(voidSelf);
    Vgreyscale__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (!vlSymsp->_vm_contextp__->calcUnusedSigs()) {
        VL_FATAL_MT(__FILE__, __LINE__, __FILE__,
            "Turning on wave traces requires Verilated::traceEverOn(true) call before time 0.");
    }
    vlSymsp->__Vm_baseCode = code;
    tracep->pushPrefix(std::string{vlSymsp->name()}, VerilatedTracePrefixType::SCOPE_MODULE);
    Vgreyscale___024root__trace_decl_types(tracep);
    Vgreyscale___024root__trace_init_top(vlSelf, tracep);
    tracep->popPrefix();
}

VL_ATTR_COLD void Vgreyscale___024root__trace_register(Vgreyscale___024root* vlSelf, VerilatedVcd* tracep);

VL_ATTR_COLD void Vgreyscale::traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options) {
    (void)levels; (void)options;
    VerilatedVcdC* const stfp = dynamic_cast<VerilatedVcdC*>(tfp);
    if (VL_UNLIKELY(!stfp)) {
        vl_fatal(__FILE__, __LINE__, __FILE__,"'Vgreyscale::trace()' called on non-VerilatedVcdC object;"
            " use --trace-fst with VerilatedFst object, and --trace-vcd with VerilatedVcd object");
    }
    stfp->spTrace()->addModel(this);
    stfp->spTrace()->addInitCb(&trace_init, &(vlSymsp->TOP));
    Vgreyscale___024root__trace_register(&(vlSymsp->TOP), stfp->spTrace());
}
