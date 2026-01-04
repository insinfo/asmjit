// This file is part of AsmJit project <https://asmjit.com>
//
// See <asmjit/core.h> or LICENSE.md for license and copyright information
// SPDX-License-Identifier: Zlib

import '../core/environment.dart';
import '../core/error.dart';
import '../core/func.dart';
import '../core/globals.dart';
import '../core/operand.dart';
import '../core/reg_type.dart';
import '../core/support.dart' as support;
import '../core/type.dart';
import '../core/func_args_context.dart';
import '../core/raconstraints.dart';
import '../core/reg_utils.dart' show Reg;

class X86FuncInternal {
  static bool shouldTreatAsCdeclIn64BitMode(CallConvId id) {
    return id == CallConvId.cdecl ||
        id == CallConvId.stdCall ||
        id == CallConvId.thisCall ||
        id == CallConvId.fastCall ||
        id == CallConvId.regParm1 ||
        id == CallConvId.regParm2 ||
        id == CallConvId.regParm3;
  }

  static AsmJitError initCallConv(CallConv cc, CallConvId id, Environment env) {
    const int kZax = 0; // Gp::kIdAx
    const int kZbx = 3; // Gp::kIdBx
    const int kZcx = 1; // Gp::kIdCx
    const int kZdx = 2; // Gp::kIdDx
    const int kZsp = 4; // Gp::kIdSp
    const int kZbp = 5; // Gp::kIdBp
    const int kZsi = 6; // Gp::kIdSi
    const int kZdi = 7; // Gp::kIdDi

    bool winAbi = env.platform == TargetPlatform.windows;

    cc.setArch(env.arch);
    cc.setSaveRestoreRegSize(RegGroup.vec, 16);
    cc.setSaveRestoreRegSize(RegGroup.mask, 8);
    cc.setSaveRestoreRegSize(RegGroup.x86Mm, 8);
    cc.setSaveRestoreAlignment(RegGroup.vec, 16);
    cc.setSaveRestoreAlignment(RegGroup.mask, 8);
    cc.setSaveRestoreAlignment(RegGroup.x86Mm, 8);

    if (env.is32Bit) {
      bool isStandard = true;
      cc.setSaveRestoreRegSize(RegGroup.gp, 4);
      cc.setSaveRestoreAlignment(RegGroup.gp, 4);

      cc.setPreservedRegs(
          RegGroup.gp, support.bitMaskMany([kZbx, kZsp, kZbp, kZsi, kZdi]));
      cc.setNaturalStackAlignment(4);

      switch (id) {
        case CallConvId.cdecl:
          break;
        case CallConvId.stdCall:
          cc.setFlags(CallConvFlags.kCalleePopsStack);
          break;
        case CallConvId.fastCall:
          cc.setFlags(CallConvFlags.kCalleePopsStack);
          cc.setPassedOrder(RegGroup.gp, kZcx, kZdx);
          break;
        case CallConvId.vectorCall:
          cc.setFlags(CallConvFlags.kCalleePopsStack);
          cc.setPassedOrder(RegGroup.gp, kZcx, kZdx);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5);
          break;
        case CallConvId.thisCall:
          if (winAbi) {
            cc.setFlags(CallConvFlags.kCalleePopsStack);
            cc.setPassedOrder(RegGroup.gp, kZcx);
          } else {
            id = CallConvId.cdecl;
          }
          break;
        case CallConvId.regParm1:
          cc.setPassedOrder(RegGroup.gp, kZax);
          break;
        case CallConvId.regParm2:
          cc.setPassedOrder(RegGroup.gp, kZax, kZdx);
          break;
        case CallConvId.regParm3:
          cc.setPassedOrder(RegGroup.gp, kZax, kZdx, kZcx);
          break;
        case CallConvId.lightCall2:
        case CallConvId.lightCall3:
        case CallConvId.lightCall4:
          int n = id.index - CallConvId.lightCall2.index + 2;
          cc.setFlags(CallConvFlags.kPassFloatsByVec);
          cc.setPassedOrder(RegGroup.gp, kZax, kZdx, kZcx, kZsi, kZdi);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPassedOrder(RegGroup.mask, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPassedOrder(RegGroup.x86Mm, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPreservedRegs(RegGroup.gp, support.lsbMask(8));
          cc.setPreservedRegs(
              RegGroup.vec, support.lsbMask(8) & ~support.lsbMask(n));
          cc.setNaturalStackAlignment(16);
          isStandard = false;
          break;
        default:
          return AsmJitError.invalidArgument;
      }

      if (isStandard) {
        cc.setPassedOrder(RegGroup.x86Mm, 0, 1, 2);
        cc.setPassedOrder(RegGroup.vec, 0, 1, 2);
        cc.addFlags(CallConvFlags.kPassVecByStackIfVA);
      }
      if (id == CallConvId.cdecl) {
        cc.addFlags(CallConvFlags.kVarArgCompatible);
      }
    } else {
      cc.setSaveRestoreRegSize(RegGroup.gp, 8);
      cc.setSaveRestoreAlignment(RegGroup.gp, 8);

      if (shouldTreatAsCdeclIn64BitMode(id)) {
        id = winAbi ? CallConvId.x64Windows : CallConvId.x64SystemV;
      }

      switch (id) {
        case CallConvId.x64SystemV:
          cc.setFlags(CallConvFlags.kPassFloatsByVec |
              CallConvFlags.kPassMmxByXmm |
              CallConvFlags.kVarArgCompatible);
          cc.setNaturalStackAlignment(16);
          cc.setRedZoneSize(128);
          cc.setPassedOrder(RegGroup.gp, kZdi, kZsi, kZdx, kZcx, 8, 9);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPreservedRegs(RegGroup.gp,
              support.bitMaskMany([kZbx, kZsp, kZbp, 12, 13, 14, 15]));
          break;
        case CallConvId.x64Windows:
          cc.setStrategy(CallConvStrategy.x64Windows);
          cc.setFlags(CallConvFlags.kPassFloatsByVec |
              CallConvFlags.kIndirectVecArgs |
              CallConvFlags.kPassMmxByGp |
              CallConvFlags.kVarArgCompatible);
          cc.setNaturalStackAlignment(16);
          cc.setSpillZoneSize(4 * 8);
          cc.setPassedOrder(RegGroup.gp, kZcx, kZdx, 8, 9);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3);
          cc.setPreservedRegs(
              RegGroup.gp,
              support
                  .bitMaskMany([kZbx, kZsp, kZbp, kZsi, kZdi, 12, 13, 14, 15]));
          cc.setPreservedRegs(RegGroup.vec,
              support.bitMaskMany([6, 7, 8, 9, 10, 11, 12, 13, 14, 15]));
          break;
        case CallConvId.vectorCall:
          cc.setStrategy(CallConvStrategy.x64VectorCall);
          cc.setFlags(
              CallConvFlags.kPassFloatsByVec | CallConvFlags.kPassMmxByGp);
          cc.setNaturalStackAlignment(16);
          cc.setSpillZoneSize(6 * 8);
          cc.setPassedOrder(RegGroup.gp, kZcx, kZdx, 8, 9);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5);
          cc.setPreservedRegs(
              RegGroup.gp,
              support
                  .bitMaskMany([kZbx, kZsp, kZbp, kZsi, kZdi, 12, 13, 14, 15]));
          cc.setPreservedRegs(RegGroup.vec,
              support.bitMaskMany([6, 7, 8, 9, 10, 11, 12, 13, 14, 15]));
          break;
        case CallConvId.lightCall2:
        case CallConvId.lightCall3:
        case CallConvId.lightCall4:
          int n = id.index - CallConvId.lightCall2.index + 2;
          cc.setFlags(CallConvFlags.kPassFloatsByVec);
          cc.setNaturalStackAlignment(16);
          cc.setPassedOrder(RegGroup.gp, kZax, kZdx, kZcx, kZsi, kZdi);
          cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPassedOrder(RegGroup.mask, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPassedOrder(RegGroup.x86Mm, 0, 1, 2, 3, 4, 5, 6, 7);
          cc.setPreservedRegs(RegGroup.gp, support.lsbMask(16));
          cc.setPreservedRegs(RegGroup.vec, ~support.lsbMask(n));
          break;
        default:
          return AsmJitError.invalidArgument;
      }
    }

    cc.setId(id);
    return AsmJitError.ok;
  }

  static RegType vecTypeIdToRegType(TypeId typeId) {
    int size = typeId.sizeInBytes;
    if (size <= 16) return RegType.vec128;
    if (size <= 32) return RegType.vec256;
    return RegType.vec512;
  }

  static void unpackValues(FuncDetail func, FuncValuePack pack) {
    TypeId typeId = pack[0].typeId;
    if (typeId == TypeId.int64 || typeId == TypeId.uint64) {
      if (func.callConv.arch.is32Bit) {
        pack[0].initTypeId(TypeId.uint32);
        pack[1].initTypeId(TypeId.values[typeId.index - 2]);
      }
    }
  }

  static AsmJitError initFuncDetail(
      FuncDetail func, FuncSignature signature, int registerSize) {
    final cc = func.callConv;
    final arch = cc.arch;
    var stackOffset = cc.spillZoneSize;
    final argCount = func.argCount;

    final gpReturnIndexes = [0, 2, Reg.kIdBad, Reg.kIdBad]; // AX, DX

    if (func.hasRet()) {
      unpackValues(func, func.rets);
      for (int i = 0; i < Globals.kMaxValuePack; i++) {
        final ret = func.rets[i];
        if (!ret.isInitialized) break;
        final typeId = ret.typeId;

        if (typeId.isInt) {
          final regId = gpReturnIndexes[i];
          if (regId != Reg.kIdBad) {
            ret.initReg(typeId.sizeInBytes <= 4 ? RegType.gp32 : RegType.gp64,
                regId, typeId);
          } else {
            return AsmJitError.invalidState;
          }
        } else if (typeId.isFloat) {
          final regType = typeId == TypeId.float80
              ? RegType.x86St
              : (arch.is32Bit ? RegType.x86St : RegType.vec128);
          ret.initReg(regType, i, typeId);
        } else if (typeId.isMmx) {
          RegType regType = RegType.x86Mm;
          int regId = i;
          if (arch.is64Bit) {
            regType = cc.strategy == CallConvStrategy.defaultStrategy
                ? RegType.vec128
                : RegType.gp64;
            regId = cc.strategy == CallConvStrategy.defaultStrategy
                ? i
                : gpReturnIndexes[i];
            if (regId == Reg.kIdBad) return AsmJitError.invalidState;
          }
          ret.initReg(regType, regId, typeId);
        } else {
          ret.initReg(vecTypeIdToRegType(typeId), i, typeId);
        }
      }
    }

    if (cc.strategy == CallConvStrategy.defaultStrategy) {
      var gpPos = 0;
      var vecPos = 0;

      for (int i = 0; i < argCount; i++) {
        unpackValues(func, func.args[i]);
        for (int j = 0; j < Globals.kMaxValuePack; j++) {
          final arg = func.args[i][j];
          if (!arg.isInitialized) break;
          final typeId = arg.typeId;

          if (typeId.isInt) {
            var regId = Reg.kIdBad;
            if (gpPos < CallConv.kMaxRegArgsPerGroup) {
              regId = cc.passedOrder(RegGroup.gp)[gpPos];
            }

            if (regId != Reg.kIdBad) {
              arg.assignRegData(
                  typeId.sizeInBytes <= 4 ? RegType.gp32 : RegType.gp64, regId);
              func.addUsedRegs(RegGroup.gp, support.bitMask(regId));
              gpPos++;
            } else {
              final size = support.max<int>(typeId.sizeInBytes, registerSize);
              arg.assignStackOffset(stackOffset);
              stackOffset += size;
            }
          } else if (typeId.isFloat || typeId.isVec) {
            var regId = Reg.kIdBad;
            if (vecPos < CallConv.kMaxRegArgsPerGroup) {
              regId = cc.passedOrder(RegGroup.vec)[vecPos];
            }

            if (typeId.isFloat && !cc.hasFlag(CallConvFlags.kPassFloatsByVec)) {
              regId = Reg.kIdBad;
            } else if (signature.hasVarArgs &&
                arch.is32Bit &&
                cc.hasFlag(CallConvFlags.kPassVecByStackIfVA)) {
              regId = Reg.kIdBad;
            }

            if (regId != Reg.kIdBad) {
              arg.assignRegData(vecTypeIdToRegType(typeId), regId);
              func.addUsedRegs(RegGroup.vec, support.bitMask(regId));
              vecPos++;
            } else {
              arg.assignStackOffset(stackOffset);
              stackOffset += typeId.sizeInBytes;
            }
          }
        }
      }
    } else {
      // Win64 strategy
      var gpPos = 0;
      var vecPos = 0;

      for (int i = 0; i < argCount; i++) {
        unpackValues(func, func.args[i]);
        for (int j = 0; j < Globals.kMaxValuePack; j++) {
          final arg = func.args[i][j];
          if (!arg.isInitialized) break;
          final typeId = arg.typeId;

          if (typeId.isInt) {
            var regId = Reg.kIdBad;
            if (gpPos < CallConv.kMaxRegArgsPerGroup) {
              regId = cc.passedOrder(RegGroup.gp)[gpPos];
            }

            if (regId != Reg.kIdBad) {
              arg.assignRegData(
                  typeId.sizeInBytes <= 4 ? RegType.gp32 : RegType.gp64, regId);
              func.addUsedRegs(RegGroup.gp, support.bitMask(regId));
              gpPos++;
            } else {
              arg.assignStackOffset(stackOffset);
              stackOffset += 8;
            }
          } else if (typeId.isFloat || typeId.isVec) {
            var regId = Reg.kIdBad;
            if (vecPos < CallConv.kMaxRegArgsPerGroup) {
              regId = cc.passedOrder(RegGroup.vec)[vecPos];
            }

            if (regId != Reg.kIdBad &&
                (typeId.isFloat ||
                    cc.strategy == CallConvStrategy.x64VectorCall)) {
              arg.assignRegData(vecTypeIdToRegType(typeId), regId);
              func.addUsedRegs(RegGroup.vec, support.bitMask(regId));
              vecPos++;
            } else {
              if (typeId.isFloat) {
                arg.assignStackOffset(stackOffset);
              } else {
                final gpId = gpPos < CallConv.kMaxRegArgsPerGroup
                    ? cc.passedOrder(RegGroup.gp)[gpPos]
                    : Reg.kIdBad;
                if (gpId != Reg.kIdBad) {
                  arg.assignRegData(RegType.gp64, gpId);
                  func.addUsedRegs(RegGroup.gp, support.bitMask(gpId));
                  gpPos++;
                } else {
                  arg.assignStackOffset(stackOffset);
                }
                arg.addFlags(FuncValueBits.kFlagIsIndirect);
              }
              stackOffset += 8;
            }
          }
        }
      }
    }

    func.setArgStackSize(stackOffset);
    return AsmJitError.ok;
  }

  static AsmJitError updateFuncFrame(
      FuncArgsAssignment assignment, FuncFrame frame) {
    final func = assignment.funcDetail;
    if (func == null) return AsmJitError.invalidState;

    final constraints = RAConstraints();
    var err = constraints.init(frame.arch);
    if (err != AsmJitError.ok) return err;

    final ctx = FuncArgsContext();
    err = ctx.initWorkData(frame, assignment, constraints);
    if (err != AsmJitError.ok) return err;

    err = ctx.markDstRegsDirty(frame);
    if (err != AsmJitError.ok) return err;

    err = ctx.markScratchRegs(frame);
    if (err != AsmJitError.ok) return err;

    return ctx.markStackArgsReg(frame);
  }
}
