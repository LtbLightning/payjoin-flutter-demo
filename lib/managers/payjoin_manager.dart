import 'dart:convert';
import 'dart:typed_data';

import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:payjoin_flutter/receive/v1.dart' as v1;
import 'package:payjoin_flutter/receive/v2.dart' as v2;
// ignore: implementation_imports
import 'package:payjoin_flutter/src/generated/utils/types.dart' as types;
import 'package:payjoin_flutter/common.dart';
import 'package:payjoin_flutter/uri.dart' as pj_uri;
import 'package:payjoin_flutter/send.dart' as send;

class PayjoinManager {
  static const pjUrl = "https://localhost:8088";
  static const ohttpRelayUrl = "https://pj.bobspacebkk.com";
  static const payjoinDirectory = "https://payjo.in";
  static const ohttpKeysPath = "/ohttp-keys";
  static const v1ContentType = "text/plain";
  static const v2ContentType = "message/ohttp-req";

  Future<String> buildV1PjStr(
    double amount,
    String address, {
    String? pj,
  }) async {
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

  Future<void> startV2ReceiveSession({
    required String address,
  }) async {
    pj_uri.OhttpKeys ohttpKeys = null;
    // Todo: update to Session in v0.18.0 with Session Initializer
    final session = await v2.Enroller.fromDirectoryConfig(
      directory: await pj_uri.Url.fromString(payjoinDirectory),
      ohttpKeys: ohttpKeys,
      ohttpRelay: await pj_uri.Url.fromString(ohttpRelayUrl),
    );

    return session;
  }

  Future<pj_uri.Uri> stringToUri(String pj) async {
    try {
      return await pj_uri.Uri.fromString(pj);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    }
  }

  Future<String> buildOriginalPsbt(
    Wallet senderWallet,
    pj_uri.Uri pjUri,
    int fee,
  ) async {
    final txBuilder = TxBuilder();
    final address = await Address.fromString(
        s: await pjUri.address(), network: Network.signet);
    final script = await address.scriptPubkey();
    double uriAmount = await pjUri.amount() ?? 0;
    int amountSat = (uriAmount * 100000000.0).round();
    final (psbt, _) = await txBuilder
        .addRecipient(script, amountSat)
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
    return psbtBase64;
  }

  Future<send.RequestContext> buildPayjoinRequest(
    Wallet senderWallet,
    pj_uri.Uri pjUri,
    int fee,
  ) async {
    final psbtBase64 = await buildOriginalPsbt(senderWallet, pjUri, fee);

    final requestBuilder = await send.RequestBuilder.fromPsbtAndUri(
        psbtBase64: psbtBase64, uri: pjUri);
    final requestContext = await requestBuilder.buildRecommended(minFeeRate: 1);

    return requestContext;
  }

  Future<String?> requestV2PayjoinProposal(
    send.RequestContext requestContext,
  ) async {
    final (request, ctx) = await requestContext.extractContextV2(
      await pj_uri.Url.fromString(payjoinDirectory),
    );
    final response = await http.post(
      Uri.parse(await request.url.asString()),
      headers: {
        'Content-Type': v2ContentType,
      },
      body: request.body,
    );
    final payjoinProposalPsbt =
        await ctx.processResponse(response: response.bodyBytes);

    return payjoinProposalPsbt;
  }

  Future<String?> handleV1Request(
    String psbtBase64,
    Wallet receiverWallet,
  ) async {
    // Normally the request with the original psbt as body, a query and headers is received
    //  by listening to a server, but we only pass the original psbt here and
    //  add the headers and a mock query ourselves.
    final List<int> body = utf8.encode(psbtBase64);

    Map<String, String> headersMap = {
      'content-type': 'text/plain',
      'content-length': body.length.toString(),
    };
    final uncheckedProposal = await v1.UncheckedProposal.fromRequest(
      body: body.toList(),
      query: '',
      headers: Headers(map: headersMap),
    );

    final proposal = await handleProposal(
        proposal: uncheckedProposal, receiverWallet: receiverWallet);

    return proposal.psbt();
  }

  Future<void> handleV2Request(Object session, Wallet receiverWallet) async {
    final (originalReq, originalCtx) = await session.extractReq();
    final originalPsbt = await http.post(
      Uri.parse(await originalReq.url.asString()),
      body: originalReq.body,
    );
    final uncheckedProposal =
        await session.processRes(originalPsbt.bodyBytes, originalCtx);
    // Todo: will need to see if a separate v2 handleProposal is needed or
    //  if the v1.UncheckedProposal can be changed to a common UncheckedProposal
    final payjoinProposal = await handleProposal(
      proposal: uncheckedProposal,
      receiverWallet: receiverWallet,
    );
    final (proposalReq, proposalCtx) = await payjoinProposal.extractV2Req();
    final proposalPsbt = await http.post(
      Uri.parse(await proposalReq.url.asString()),
      body: proposalReq.body,
    );
    await payjoinProposal.processRes(proposalPsbt.bodyBytes, proposalCtx);
  }

  Future<String> processV1Proposal(
    send.RequestContext reqCtx,
    String proposalPsbt,
  ) async {
    final (_, ctx) = await reqCtx.extractContextV1();
    final checkedProposal =
        await ctx.processResponse(response: utf8.encode(proposalPsbt));
    debugPrint('Processed Response: $checkedProposal');
    return checkedProposal;
  }

  Future<String> processV2Proposal(
    send.RequestContext reqCtx,
    String proposalPsbt,
  ) async {
    final (_, ctx) = await reqCtx.extractContextV2(
      await pj_uri.Url.fromString(payjoinDirectory),
    );
    final checkedProposal =
        await ctx.processResponse(response: utf8.encode(proposalPsbt));
    debugPrint('Processed Response: $checkedProposal');
    return checkedProposal!; // Since this is called after the original request, the response should not be null
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
