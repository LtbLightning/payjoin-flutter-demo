import 'dart:convert';
import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:payjoin_flutter/receive/v1.dart' as v1;
import 'package:payjoin_flutter/receive/v1.dart';
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/uri.dart' as pj_uri;
import 'package:payjoin_flutter/send.dart' as send;

class PayjoinManager {
  static const pjUrl = "https://localhost:8088";

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
      return await pj_uri.Uri.fromString(pj);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  //Sender psbt
  Future<(Request, send.ContextV1)> buildPayjoinRequest(
      Wallet senderWallet, pj_uri.Uri pjUri, int fee) async {
    final txBuilder = TxBuilder();
    final address = await Address.fromString(
        s: await pjUri.address(), network: Network.signet);
    final script = await address.scriptPubkey();
    int amount = (((await pjUri.amount()) ?? 0) * 100000000).toInt();
    final (psbt, _) = await txBuilder
        .addRecipient(script, amount)
        .feeAbsolute(fee)
        .finish(senderWallet);
    await senderWallet.sign(
      psbt: psbt,
      signOptions: const SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: true,
        tryFinalize: true,
        signWithTapInternalKey: true,
        allowGrinding: false,
      ),
    );

    final psbtBase64 = await psbt.serialize();
    debugPrint('Original Sender Psbt for request: $psbtBase64');

    final requestBuilder = await send.RequestBuilder.fromPsbtAndUri(
        psbtBase64: psbtBase64, uri: pjUri);
    final requestContext = await requestBuilder.buildRecommended(minFeeRate: 1);

    return requestContext.extractContextV1();
  }

  Future<String?> handlePjRequest(String psbtBase64, receiverWallet) async {
    // Normally the request with the original psbt as body, a query and headers is received
    //  by listening to a server, but we only pass the original psbt here and
    //  add the headers and a mock query ourselves.
    final List<int> body = utf8.encode(psbtBase64);

    Map<String, String> headersMap = {
      'content-type': 'text/plain',
      'content-length': body.length.toString(),
    };
    final uncheckedProposal = await UncheckedProposal.fromRequest(
      body: body,
      query: '',
      headers: Headers(map: headersMap),
    );

    final proposal = await handleProposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return proposal.psbt();
  }

  Future<bool> isOwned(Uint8List bytes, Wallet wallet) async {
    final script = ScriptBuf(bytes: bytes);
    return await wallet.isMine(script: script);
  }

  Future<String> processPsbt(String preProcessed, Wallet wallet) async {
    final psbt = await PartiallySignedTransaction.fromString(preProcessed);
    print('PSBT before: ${await psbt.serialize()}');
    await wallet.sign(
      psbt: psbt,
      signOptions: const SignOptions(
        trustWitnessUtxo: true,
        allowAllSighashes: false,
        removePartialSigs: true,
        tryFinalize: true,
        signWithTapInternalKey: true,
        allowGrinding: false,
      ),
    );
    print('PSBT after: ${await psbt.serialize()}');
    return psbt.serialize();
  }

  Future<v1.PayjoinProposal> handleProposal({
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
      final payjoin =
          await (await seenInputs.checkNoInputsSeenBefore(isKnown: (e) async {
        return false;
      }))
              .identifyReceiverOutputs(
        isReceiverOutput: (i) => isOwned(i, receiverWallet),
      );

      final availableInputs = await receiverWallet.listUnspent();
      Map<int, types.OutPoint> candidateInputs = {
        for (var input in availableInputs)
          input.txout.value: types.OutPoint(
            txid: input.outpoint.txid.toString(),
            vout: input.outpoint.vout,
          )
      };
      final selectedOutpoint = await payjoin.tryPreservingPrivacy(
        candidateInputs: candidateInputs,
      );
      var selectedUtxo = availableInputs.firstWhere(
          (i) =>
              i.outpoint.txid == selectedOutpoint.txid &&
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
        txo: txoToContribute,
        outpoint: outpointToContribute,
      );
      final newReceiverAddress = await ((await receiverWallet.getAddress(
                  addressIndex: const AddressIndex.increase()))
              .address)
          .asString();
      payjoin.substituteOutputAddress(address: newReceiverAddress);
      final payjoinProposal = await payjoin.finalizeProposal(
          processPsbt: (i) => processPsbt(i, receiverWallet));
      return payjoinProposal;
    } on Exception catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<Transaction> extractPjTx(
      Wallet senderWallet, String psbtString) async {
    final psbt = await PartiallySignedTransaction.fromString(psbtString);
    print('PSBT before: ${await psbt.serialize()}');
    senderWallet.sign(
        psbt: psbt,
        signOptions: const SignOptions(
            trustWitnessUtxo: true,
            allowAllSighashes: false,
            removePartialSigs: true,
            tryFinalize: true,
            signWithTapInternalKey: true,
            allowGrinding: false));
    print('PSBT after: ${await psbt.serialize()}');
    var transaction = await psbt.extractTx();
    return transaction;
  }
}
