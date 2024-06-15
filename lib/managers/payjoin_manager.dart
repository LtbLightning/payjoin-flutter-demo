import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:payjoin_flutter/receive/v1.dart' as v1;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/uri.dart' as uri;

class PayjoinManager {
  Future<String> buildPjUri(double amount, String address, String pj) async {
    try {
      final pjUri = "bitcoin:$address?amount=${amount / 100000000.0}&pj=$pj";
    //  await uri.Uri.fromString(pjUri);
      return pjUri;
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  //Sender psbt
  Future<PartiallySignedTransaction> buildOriginalPsbt(
      senderWallet, String pjUri, double feeRate) async {
    final txBuilder = TxBuilder();
    final pjUriStr = await uri.Uri.fromString(pjUri);

    final address = await Address.fromString(
        s: await pjUriStr.address(), network: Network.testnet);
    final script = await address.scriptPubkey();

    final psbt = await txBuilder
        .addRecipient(script, await pjUriStr.amount() ?? 100)
        .feeRate(feeRate)
        .finish(senderWallet);
    print("psbt : ${psbt.$1}");
    print(psbt.$2);
    return psbt.$1;
  }

  Future<String?> handlePjRequest(
      Request req, Headers headers, receiverWallet) async {
    final uncheckedProposal = await v1.UncheckedProposal.fromRequest(
        body: req.body.toList(),
        query: (await req.url.query())!,
        headers: headers);

    final proposal = await handleProposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return await proposal?.psbt();
  }

  Future<bool> isReceiverOutput(Uint8List bytes, Wallet wallet) async {
    return true;
  }

  Future<bool> isKnown(types.OutPoint outputScript, Wallet wallet) async {
    return true;
  }

  Future<bool> canBroadcast(Uint8List bytes, Wallet wallet) async {
    return true;
  }

  Future<bool> isOwned(Uint8List bytes, Wallet wallet) async {
    final script = ScriptBuf(bytes: bytes);
    return await wallet.isMine(script: script);
  }

  Future<String> processPsbt(String preProcessed, Wallet wallet) async {
    final psbt = await PartiallySignedTransaction.fromString(preProcessed);
    final isFinalized = await wallet.sign(psbt: psbt);
    if (isFinalized) {
      return await psbt.serialize();
    } else {
      throw Exception("The psbt can not finalized");
    }
  }

  Future<v1.PayjoinProposal?> handleProposal(
      {required v1.UncheckedProposal proposal,
      required Wallet receiverWallet,
      senderAddress}) async {
    try {
      final _ = await proposal.extractTxToScheduleBroadcast();
      final ownedInput = await proposal.checkBroadcastSuitability(
          canBroadcast: (i) => canBroadcast(i, receiverWallet));
      final outputsOwned = await ownedInput.checkInputsNotOwned(
          isOwned: (i) => isOwned(i, receiverWallet));
      final seenInput = await outputsOwned.checkNoMixedInputScripts();
      final outputsUnknown = (await seenInput.checkNoInputsSeenBefore(
          isKnown: (i) => isKnown(i, receiverWallet))); //?ptr
      final payjoin = await outputsUnknown.identifyReceiverOutputs(
        isReceiverOutput: (i) => isReceiverOutput(i, receiverWallet),
      );
      final availableInputs = await receiverWallet.listUnspent();
      Map<int, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
              txid: input.outpoint.txid.toString(), vout: input.outpoint.vout)
      };
      final selectedOutpoint =
          await payjoin.tryPreservingPrivacy(candidateInputs: candidateInputs);
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
      payjoin.contributeWitnessInput(
          txo: txoToContribute, outpoint: outpointToContribute);
      payjoin.substituteOutputAddress(address: senderAddress!);

      final payjoinProposal = await payjoin.finalizeProposal(
          processPsbt: (i) => processPsbt(i, receiverWallet));
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
    }
    return null;
  }
}
