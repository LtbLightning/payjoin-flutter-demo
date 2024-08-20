import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/receive/v1.dart' as v1;
import 'package:payjoin_flutter/send.dart' as send;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/uri.dart' as pj_uri;
import 'package:payjoin_flutter_demo/managers/bdk_manager.dart';

class PayJoinManager {
  static const pjUrl = "https://localhost:8088";
  final bdkManager = BdkManager();
  Future<String> buildPjStr(double amount, String address, {String? pj}) async {
    try {
      final pjUri =
          "bitcoin:$address?amount=${amount / 100000000.0}&pj=${pj ?? pjUrl}";
      debugPrint("pjUri: : $pjUri");
      return pjUri;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<pj_uri.Uri> stringToUri(String pj) async {
    try {
      return await pj_uri.Uri.fromStr(pj);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

//please century boy hobby blade nothing clinic okay fit kitten detail horn
  Future<(String?, send.ContextV1)> handlePjRequest(
      String psbtBase64, pj_uri.PjUri uri, receiverWallet) async {
    final (req, cxt) = await (await (await send.RequestBuilder.fromPsbtAndUri(
                psbtBase64: psbtBase64, pjUri: uri))
            .buildWithAdditionalFee(
                maxFeeContribution: BigInt.from(1000),
                minFeeRate: BigInt.from(0),
                clampFeeContribution: false))
        .extractV1();

    final headers = Headers(map: {
      'content-type': 'text/plain',
      'content-length': req.body.length.toString(),
    });
    final uncheckedProposal = await v1.UncheckedProposal.fromRequest(
        body: req.body.toList(), query: (req.url.query())!, headers: headers);

    final proposal = await handleProposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return (await proposal?.psbt(), cxt);
  }

  Future<bool> isReceiverOutput(Uint8List bytes, Wallet wallet) async {
    return true;
  }

  Future<bool> isOwned(Uint8List bytes, Wallet wallet) async {
    final script = ScriptBuf(bytes: bytes);
    return wallet.isMine(script: script);
  }

  Future<String> processPsbt(String preProcessed, Wallet receiverWallet) async {
    return (await bdkManager.signPsbt(preProcessed, receiverWallet))!
        .toString();
  }

  Future<v1.PayjoinProposal?> handleProposal({
    required v1.UncheckedProposal proposal,
    required Wallet receiverWallet,
  }) async {
    try {
      final _ = await proposal.extractTxToScheduleBroadcast();
      final ownedInputs =
          await proposal.checkBroadcastSuitability(canBroadcast: (e) async {
        return true;
      });
      final mixedInputScripts = await ownedInputs.checkInputsNotOwned(
          isOwned: (i) => isOwned(i, receiverWallet));
      final seenInputs = await mixedInputScripts.checkNoMixedInputScripts();
      final provisionalProposal =
          await (await seenInputs.checkNoInputsSeenBefore(isKnown: (e) async {
        return false;
      }))
              .identifyReceiverOutputs(
        isReceiverOutput: (i) => isReceiverOutput(i, receiverWallet),
      );

      final availableInputs = receiverWallet.listUnspent();
      Map<BigInt, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
              txid: input.outpoint.txid.toString(), vout: input.outpoint.vout)
      };
      final selectedOutpoint = await provisionalProposal.tryPreservingPrivacy(
          candidateInputs: candidateInputs);
      var selectedUtxo = availableInputs.firstWhere(
          (i) =>
              i.outpoint.txid.toString() == selectedOutpoint.txid &&
              i.outpoint.vout == selectedOutpoint.vout,
          orElse: () => throw Exception('UTXO not found'));
      var txoToContribute = types.TxOut(
        value: selectedUtxo.txout.value,
        scriptPubkey: selectedUtxo.txout.scriptPubkey.bytes,
      );

      var outpointToContribute = types.OutPoint(
        txid: selectedUtxo.outpoint.txid.toString(),
        vout: selectedUtxo.outpoint.vout,
      );
      provisionalProposal.contributeWitnessInput(
          txo: txoToContribute, outpoint: outpointToContribute);
      final payjoinProposal = await provisionalProposal.finalizeProposal(
          processPsbt: (i) => processPsbt(i, receiverWallet));
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }
}
