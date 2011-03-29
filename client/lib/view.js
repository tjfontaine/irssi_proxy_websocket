var View = function() {
  
}

View.prototype.add_window = function(name, index) {
  $('#content').tabs('add', '#'+index, name, 0)
  $('#'+name).addClass('container')
  var item = $('#content li').get(0)
  $(item).data('index', parseInt(index))
}

View.prototype.del_window = function(win) {
  $('#content').tabs('remove', win)
  this.sort_windows()
}

View.prototype.set_window_activity = function(win, level) {
  /* data_level - 0=no new data, 1=text, 2=msg, 3=highlighted text */
  win = parseInt(win)
  if(win != this.current_window || level == 0) {
    var idx = win + 1
    var li = $('#content ul li:nth-child('+idx+') span')
    var cur = parseInt(li.text().replace(/[*!+]/, ''))
    
    if(cur == win){
      cur = this.activity_name(cur, level)
      li.text(cur)
    }
  }
}

View.prototype.activity_name = function(cur, level) {
  switch(level) {
    case 0:
      break;
    case 1:
      cur += '+'
      break;
    case 2:
      cur += '*'
      break;
    case 3:
      cur += '!'
      break;
  }
  return cur;
}

/*View.prototype.current_window = function() {
  var idx = $('#content').tabs('option', 'selected')
  idx = $($('#content li').get(idx)).data('index')
  return idx
}*/

View.prototype.set_content = function(win, lines) {
  $('#'+win).append('<pre>'+lines.join("\n")+'\n</pre>')
}

View.prototype.append_message = function(win, msg) {
  $('#'+win).html($('#'+win).html().replace(/<\/pre>$/, msg + '\n</pre>'))
}

View.prototype.clear_window = function(win) {
  $('#'+win).html('')
}

View.prototype.scroll_to_bottom = function(win) {
  var tab = $('#'+win)[0]
  tab.scrollTop = tab.scrollHeight;  
}

View.prototype.log = function(msg) {
  var now = new Date()
  var time = [now.getHours(), now.getMinutes(), now.getSeconds(), now.getMilliseconds()]
  this.append_message('0', time.join(':') + ' ==> ' + msg)
}

View.prototype.sort_windows = function(event, ui) {
  $('#content li').sort(function(a, b){
    var ai = $(a).data('index')
    var bi = $(b).data('index')
    return ai > bi ? 1 : -1;
  }).appendTo('#content ul')
}