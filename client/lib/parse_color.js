var ic = [ 0, 4, 2, 6, 1, 5, 3, 7,
           0, 4, 2, 6, 1, 5, 3, 7 ];
var ih = [ '', '', '', '', '', '', '', '', 
           1, 1, 1, 1, 1, 1, 1, 1 ];

var bols = ['bold', 'underline', 'blink', 'reverse', 'fgh', 'bgh']
var cn   = ['black', 'dr', 'dg', 'dy', 'db', 'dm', 'dc', 'lgray',
            'dgray', 'lr', 'lg', 'ly', 'lb', 'lm', 'lc', 'white']

ParseColor = function(line) {
  var state = {}
  var newline = ''

  function set_default_colors() {
    state.fgc = state.bgc = -1;
    state.fgh = state.bgh = 0;
  }

  function set_default_modes() {
    state.bold = state.underline = state.blink = state.reverse = 0;
  }

  function set_default() {
    set_default_colors()
    set_default_modes()
  }

  var oldclass = undefined;

  function emit(character) {
    var cls = {}

    for (var i in bols) {
      var b = bols[i]
      if (state[b]) {
        if (!cls[b]) {
          cls[b] = 0
        }
        cls[b] += 1
      }
    }

    var fgbg = ['fg', 'bg']
    for (var i in fgbg) {
      var e = fgbg[i]
      var h = cls[e+'h'];
      delete cls[e+'h'];

      var n = state[e+'c'];
      if (n >= 0) {
        if(!h) { h = 0 }
        var z = n + 8 * h;
        var clr = cn[z]
        var k = e+clr
        if (!cls[k]) {
          cls[k] = 0
        }
        cls[k] += 1
      }
    }

    var cls_keys = []
    for (var i in cls) {
      cls_keys.push(i)
    }
    var cls_string = cls_keys.join(' ')

    if (oldclass) {
      newline += '</span>'
    }

    if (cls_string) {
      newline += '<span class="'+cls_string+'">'
    }

    oldclass = cls_string

    character = character.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    newline += character
  }

  set_default();

  while(line.length) {
    if((/^\cD/).test(line)) {
      line = line.replace(/^\cD/, '')

      if        ((/^a/).test(line)) {
        line = line.replace(/^a/, '')
        state.blink = !state.blink
      } else if ((/^b/).test(line)) {
        line = line.replace(/^b/, '')
        state.underline = !state.underline
      } else if ((/^c/).test(line)) {
        line = line.replace(/^c/, '')
        state.bold = !state.bold
      } else if ((/^d/).test(line)) {
        line = line.replace(/^d/, '')
      } else if ((/^e/).test(line)) {
        line = line.replace(/^e/, '')
      } else if ((/^f/).test(line)) {
        line = line.replace(/^f([^,]*),/, '')
      } else if ((/^g/).test(line)) {
        line = line.replace(/^g/, '')
        set_default()
      } else if ((/^h/).test(line)) {
        line = line.replace(/^h/, '')
      } else if ((/^i/).test(line)) {
        line = line.replace(/^i/, '')
      } else {
        var foreground = line.charCodeAt(0) - '0'.charCodeAt(0);
        var background = line.charCodeAt(1) - '0'.charCodeAt(0);
        line = line.substr(2);
        if(foreground > 0) {
          state.fgc = ic[foreground];
          state.fgh = ih[foreground];
        }
        if(background > 0) {
          state.bgc = ic[background];
          state.bgh = ih[background];
        }
      }
    } else {
      var re = line.match(/^(.[^\cB\cC\cD\cF\cO\cV\c[\c_]*)/);
      line = line.replace(/^(.[^\cB\cC\cD\cF\cO\cV\c[\c_]*)/, '');
      emit(re[1]);
    }
  }

  emit('')
  return newline
}
