import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:rxdart/rxdart.dart';

import './enums.dart';

/// Bluetooth printer
class PrinterBluetooth {
  PrinterBluetooth(this.device);
  final BluetoothDevice device;

  String get name => device.name;
  String get address => device.address;
  BluetoothDeviceType get type => device.type;
}

/// Printer Bluetooth Manager
class BluetoothDiscoveryManager {
  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);
  StreamSubscription _isScanningSubscription;
  StreamSubscription _scanResultsSubscription;

  BluetoothDiscoveryManager() {}
  final FlutterBluetoothSerial _bluetoothManager =
      FlutterBluetoothSerial.instance;

  Stream<bool> get isScanningStream => _isScanning.stream;

  final BehaviorSubject<List<PrinterBluetooth>> _scanResults =
      BehaviorSubject.seeded([]);
  Stream<List<PrinterBluetooth>> get scanResults => _scanResults.stream;

  void startScan(Duration timeout) async {
    _scanResults.add(<PrinterBluetooth>[]);

    _scanResultsSubscription =
        _bluetoothManager.startDiscovery().listen((scanResult) {
      final oldData = _scanResults.value;
      oldData.add(PrinterBluetooth(scanResult.device));
      _scanResults.add(oldData);
    });
  }

  void stopScan() async {
    await _bluetoothManager.startDiscovery();
  }

  Future<void> dispose() async {
    await _isScanning.drain();
    _isScanning.close();
    await _isScanningSubscription.cancel();
    await _scanResultsSubscription.cancel();
  }
}

class BluetoothPrinterManager {
  String address;
  BluetoothConnection _connection;
  bool _isPrinting = false;
  BluetoothPrinterManager({
    @required this.address,
  }) : assert(address != null);

  Future<void> connect() async {
    _connection = await BluetoothConnection.toAddress(address);
  }

  Future<void> disConnect() => _connection?.finish();

  Future _runDelayed(int seconds) {
    return Future<dynamic>.delayed(Duration(seconds: seconds));
  }

  Future<PosPrintResult> writeBytes(
    List<int> bytes, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    final Completer<PosPrintResult> completer = Completer();

    const int timeout = 5;
    if (_connection == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    } else if (_connection.isConnected) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }

    _isPrinting = true;

    final len = bytes.length;
    for (var i = 0; i < len; i += chunkSizeBytes) {
      var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
      _connection.output.add(Uint8List.fromList(bytes.sublist(i, end)));
      sleep(Duration(milliseconds: queueSleepTimeMs));
    }

    completer.complete(PosPrintResult.success);

    //  await _bluetoothManager.connect(_selectedPrinter._device);
    // _selectedPrinter.device.state.listen((event) async {
    //   switch (event) {
    //     case BluetoothDeviceState.disconnected:
    //       _isConnected = false;
    //       break;
    //       break;
    //     case BluetoothDeviceState.connecting:
    //       // TODO: Handle this case.
    //       break;
    //     case BluetoothDeviceState.connected:

    //       // To avoid double call
    //       if (!_isConnected) {
    //         final len = bytes.length;
    //         List<List<int>> chunks = [];
    //         for (var i = 0; i < len; i += chunkSizeBytes) {
    //           var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
    //           chunks.add(bytes.sublist(i, end));
    //         }

    //         for (var i = 0; i < chunks.length; i += 1) {
    //           var service = await _selectedPrinter.device.discoverServices();
    //           service.first.characteristics.first.write(chunks[i]);
    //           sleep(Duration(milliseconds: queueSleepTimeMs));
    //         }

    //         completer.complete(PosPrintResult.success);
    //       }
    //       // TODO sending disconnect signal should be event-based
    //       _runDelayed(3).then((dynamic v) async {
    //         await _selectedPrinter.device.disconnect();
    //         _isPrinting = false;
    //       });
    //       _isConnected = true;
    //       break;
    //       break;
    //     case BluetoothDeviceState.disconnecting:
    //       _isConnected = false;
    //       break;
    //   }
    // });
    // Subscribe to the events
    // _bluetoothManager.state.listen((state) async {
    //   switch (state) {
    //     case BluetoothManager.CONNECTED:
    //       // To avoid double call
    //       if (!_isConnected) {
    //         final len = bytes.length;
    //         List<List<int>> chunks = [];
    //         for (var i = 0; i < len; i += chunkSizeBytes) {
    //           var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
    //           chunks.add(bytes.sublist(i, end));
    //         }

    //         for (var i = 0; i < chunks.length; i += 1) {
    //           await _bluetoothManager.writeData(chunks[i]);
    //           sleep(Duration(milliseconds: queueSleepTimeMs));
    //         }

    //         completer.complete(PosPrintResult.success);
    //       }
    //       // TODO sending disconnect signal should be event-based
    //       _runDelayed(3).then((dynamic v) async {
    //         await _bluetoothManager.disconnect();
    //         _isPrinting = false;
    //       });
    //       _isConnected = true;
    //       break;
    //     case BluetoothManager.DISCONNECTED:
    //       _isConnected = false;
    //       break;
    //     default:
    //       break;
    //    }
    // });

    // Printing timeout
    _runDelayed(timeout).then((dynamic v) async {
      if (_isPrinting) {
        _isPrinting = false;
        completer.complete(PosPrintResult.timeout);
      }
    });

    return completer.future;
  }

  Future<PosPrintResult> printTicket(
    Ticket ticket, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    if (ticket == null || ticket.bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    return writeBytes(
      ticket.bytes,
      chunkSizeBytes: chunkSizeBytes,
      queueSleepTimeMs: queueSleepTimeMs,
    );
  }
}
