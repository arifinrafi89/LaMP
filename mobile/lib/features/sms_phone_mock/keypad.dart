/// A basic phone's keypad (plan 5.7): multi-tap letters, `#` switches
/// letters and numbers, `*` deletes. Pure, so it is tested on its own.
library;

/// What each key gives, in turn, while typing letters; the digit ends the
/// cycle, as on a real basic phone.
const keyLetters = {
  '1': '-1',
  '2': 'ABC2',
  '3': 'DEF3',
  '4': 'GHI4',
  '5': 'JKL5',
  '6': 'MNO6',
  '7': 'PQRS7',
  '8': 'TUV8',
  '9': 'WXYZ9',
  '0': ' 0',
};

class MultiTap {
  MultiTap({this.window = const Duration(milliseconds: 900)});

  /// Pressing the same key again within this time picks its next letter.
  final Duration window;

  String _text = '';
  String get text => _text;

  bool _letters = true;
  bool get letters => _letters;

  String? _lastKey;
  DateTime? _lastAt;
  int _cycle = 0;

  void press(String key, DateTime now) {
    switch (key) {
      case '*':
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
        _settle();
        return;
      case '#':
        _letters = !_letters;
        _settle();
        return;
    }
    final group = keyLetters[key];
    if (group == null) return;
    if (!_letters) {
      _text += key;
      _settle();
      return;
    }
    final again = key == _lastKey && _lastAt != null && now.difference(_lastAt!) < window && _text.isNotEmpty;
    if (again) {
      _cycle = (_cycle + 1) % group.length;
      _text = _text.substring(0, _text.length - 1) + group[_cycle];
    } else {
      _cycle = 0;
      _text += group[0];
    }
    _lastKey = key;
    _lastAt = now;
  }

  /// The presenter's shortcut: a whole text at once.
  void fill(String text) {
    _text = text;
    _settle();
  }

  void clear() {
    _text = '';
    _settle();
  }

  void _settle() {
    _lastKey = null;
    _lastAt = null;
    _cycle = 0;
  }
}
