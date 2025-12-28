// This file is part of AsmJit project <https://asmjit.com>
//

import '../core/arch.dart';
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

class A64FuncInternal {
  static bool shouldTreatAsCdecl(CallConvId id) {
    return id == CallConvId.cdecl ||
        id == CallConvId.stdCall ||
        id == CallConvId.fastCall ||
        id == CallConvId.vectorCall ||
        id == CallConvId.thisCall ||
        id == CallConvId.regParm1 ||
        id == CallConvId.regParm2 ||
        id == CallConvId.regParm3;
  }

  static RegType regTypeFromFpOrVecTypeId(TypeId typeId) {
    if (typeId == TypeId.float32) {
      return RegType.vec32;
    } else if (typeId == TypeId.float64) {
      return RegType.vec64;
    } else if (typeId.isVec32) {
      return RegType.vec32;
    } else if (typeId.isVec64) {
      return RegType.vec64;
    } else if (typeId.isVec128) {
      return RegType.vec128;
    } else {
      return RegType.none;
    }
  }

  static AsmJitError initCallConv(CallConv cc, CallConvId id, Environment env) {
    cc.setArch(env.arch);
    cc.setStrategy(env.platform == TargetPlatform.macos
        ? CallConvStrategy.aarch64Apple
        : CallConvStrategy.defaultStrategy);

    cc.setSaveRestoreRegSize(RegGroup.gp, 8);
    cc.setSaveRestoreRegSize(RegGroup.vec, 8);
    cc.setSaveRestoreAlignment(RegGroup.gp, 16);
    cc.setSaveRestoreAlignment(RegGroup.vec, 16);
    cc.setSaveRestoreAlignment(RegGroup.mask, 8);
    cc.setSaveRestoreAlignment(RegGroup.extra, 1);
    cc.setPassedOrder(RegGroup.gp, 0, 1, 2, 3, 4, 5, 6, 7);
    cc.setPassedOrder(RegGroup.vec, 0, 1, 2, 3, 4, 5, 6, 7);
    cc.setNaturalStackAlignment(16);

    if (shouldTreatAsCdecl(id)) {
      cc.setId(CallConvId.cdecl);
      // Gp::kIdOs = 18.
      cc.setPreservedRegs(
          RegGroup.gp,
          support.bitMaskMany(
              [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]));
      cc.setPreservedRegs(
          RegGroup.vec, support.bitMaskMany([8, 9, 10, 11, 12, 13, 14, 15]));
    } else {
      cc.setId(id);
      cc.setSaveRestoreRegSize(RegGroup.vec, 16);
      cc.setPreservedRegs(
          RegGroup.gp,
          support.bitMaskMany([
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            25,
            26,
            27,
            28,
            29,
            30
          ]));
      cc.setPreservedRegs(
          RegGroup.vec,
          support.bitMaskMany([
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            25,
            26,
            27,
            28,
            29,
            30,
            31
          ]));
    }

    return AsmJitError.ok;
  }

  static AsmJitError initFuncDetail(
      FuncDetail func, FuncSignature signature, int registerSize) {
    final cc = func.callConv;
    final argCount = func.argCount;
    var stackOffset = 0;

    int minStackArgSize = cc.strategy == CallConvStrategy.aarch64Apple ? 4 : 8;

    if (func.hasRet()) {
      for (int i = 0; i < Globals.kMaxValuePack; i++) {
        final ret = func.rets[i];
        if (!ret.isInitialized) break;
        final typeId = ret.typeId;

        switch (typeId) {
          case TypeId.int8:
          case TypeId.int16:
          case TypeId.int32:
            ret.initReg(RegType.gp32, i, TypeId.int32);
            break;
          case TypeId.uint8:
          case TypeId.uint16:
          case TypeId.uint32:
            ret.initReg(RegType.gp32, i, TypeId.uint32);
            break;
          case TypeId.int64:
          case TypeId.uint64:
            ret.initReg(RegType.gp64, i, typeId);
            break;
          default:
            final regType = regTypeFromFpOrVecTypeId(typeId);
            if (regType == RegType.none) return AsmJitError.invalidRegType;
            ret.initReg(regType, i, typeId);
            break;
        }
      }
    }

    if (cc.strategy == CallConvStrategy.defaultStrategy ||
        cc.strategy == CallConvStrategy.aarch64Apple) {
      var gpPos = 0;
      var vecPos = 0;

      for (int i = 0; i < argCount; i++) {
        final arg = func.args[i][0];
        final typeId = arg.typeId;

        if (typeId.isInt) {
          var regId = Reg.kIdBad;
          if (gpPos < CallConv.kMaxRegArgsPerGroup) {
            regId = cc.passedOrder(RegGroup.gp)[gpPos];
          }

          if (regId != Reg.kIdBad) {
            final regType =
                typeId.sizeInBytes <= 4 ? RegType.gp32 : RegType.gp64;
            arg.assignRegData(regType, regId);
            func.addUsedRegs(RegGroup.gp, support.bitMask(regId));
            gpPos++;
          } else {
            var size = support.max(typeId.sizeInBytes, minStackArgSize);
            if (size >= 8) {
              stackOffset = support.alignUp(stackOffset, 8);
            }
            arg.assignStackOffset(stackOffset);
            stackOffset += size;
          }
          continue;
        }

        if (typeId.isFloat || typeId.isVec) {
          var regId = Reg.kIdBad;
          if (vecPos < CallConv.kMaxRegArgsPerGroup) {
            regId = cc.passedOrder(RegGroup.vec)[vecPos];
          }

          if (regId != Reg.kIdBad) {
            final regType = regTypeFromFpOrVecTypeId(typeId);
            if (regType == RegType.none) return AsmJitError.invalidRegType;
            arg.assignRegData(regType, regId);
            func.addUsedRegs(RegGroup.vec, support.bitMask(regId));
            vecPos++;
          } else {
            var size = support.max(typeId.sizeInBytes, minStackArgSize);
            if (size >= 8) {
              stackOffset = support.alignUp(stackOffset, 8);
            }
            arg.assignStackOffset(stackOffset);
            stackOffset += size;
          }
          continue;
        }
      }
    } else {
      return AsmJitError.invalidState;
    }

    func.setArgStackSize(support.alignUp(stackOffset, 8));
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

void registerA64FuncLogic() {
  registerArchFuncLogic(ArchFamily.aarch64, A64FuncInternal.initCallConv,
      A64FuncInternal.initFuncDetail, A64FuncInternal.updateFuncFrame);
}
