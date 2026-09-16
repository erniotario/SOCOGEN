import 'package:flutter/foundation.dart';

/// Global signal broadcast whenever data is created, updated or deleted
/// anywhere in the app. Screens stay alive inside an [IndexedStack], so
/// switching tabs does not by itself reload their cached data — each
/// screen listens here and reloads when another screen reports a change
/// (e.g. a magasin added/deleted on the Magasins screen must refresh the
/// store lists shown on Produits, Entrées, Sorties, etc.).
class DataRefreshBus extends ChangeNotifier {
  DataRefreshBus._();
  static final DataRefreshBus instance = DataRefreshBus._();

  void notifyChanged() => notifyListeners();
}
