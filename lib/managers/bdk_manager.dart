import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:flutter/foundation.dart';

class BdkManager {
  Future<List<Descriptor>> getDescriptors(
      String mnemonicStr, Network network) async {
    final descriptors = <Descriptor>[];
    try {
      for (var e in [KeychainKind.externalChain, KeychainKind.internalChain]) {
        final mnemonic = await Mnemonic.fromString(mnemonicStr);
        final descriptorSecretKey = await DescriptorSecretKey.create(
          network: network,
          mnemonic: mnemonic,
        );
        final descriptor = await Descriptor.newBip86(
            secretKey: descriptorSecretKey, network: network, keychain: e);
        descriptors.add(descriptor);
      }
      return descriptors;
    } on Exception {
      rethrow;
    }
  }

  ///Step2:Client
  Future<Blockchain> blockchainInit(String esploraUrl) async {
    try {
      return await Blockchain.create(
          config: BlockchainConfig.esplora(
              config: EsploraConfig(baseUrl: esploraUrl, stopGap: 10)));
    } on Exception catch (e) {
      rethrow;
    }
  }

  Future<Wallet> createOrRestoreWallet(
    String mnemonic,
    Network network,
    String? password,
  ) async {
    try {
      final descriptors = await getDescriptors(mnemonic, network);
      final res = await Wallet.create(
          descriptor: descriptors[0],
          changeDescriptor: descriptors[1],
          network: network,
          databaseConfig: const DatabaseConfig.memory());
      return res;
    } on Exception {
      rethrow;
    }
  }

  Future<Balance> getBalance(Wallet wallet) async {
    return await wallet.getBalance();
  }

  Future<AddressInfo> getNewAddress(Wallet wallet) async {
    final res =
        await wallet.getAddress(addressIndex: const AddressIndex.increase());
    return res;
  }

  Future<PartiallySignedTransaction> buildPsbt(
      Wallet wallet, String address, int amount, double feeRate) async {
    final txBuilder = TxBuilder();
    final script = await (await Address.fromString(
            s: address, network: await wallet.network()))
        .scriptPubkey();
    final psbt = await txBuilder
        .addRecipient(script, amount)
        .feeRate(feeRate)
        .finish(wallet);
    return psbt.$1;
  }

  Future<PartiallySignedTransaction?> signPsbt(
      String unsigned, Wallet wallet) async {
    try {
      final psbt = await PartiallySignedTransaction.fromString(unsigned);
      await wallet.sign(
          psbt: psbt,
          signOptions: const SignOptions(
              trustWitnessUtxo: true,
              allowAllSighashes: true,
              removePartialSigs: true,
              tryFinalize: true,
              signWithTapInternalKey: true,
              allowGrinding: true));
      return psbt;
    } on Exception catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
      return null;
    }
  }

  Future<Transaction> extractTxFromPsbtString(
      Wallet wallet, String psbtString) async {
    final psbt = await signPsbt(psbtString, wallet);
    var transaction = await psbt?.extractTx();
    return transaction!;
  }
}
