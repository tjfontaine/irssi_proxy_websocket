var View = function() {
  
}

View.prototype.add_window = function(name, index) {
  $('#content').tabs('add', '#'+name, name, parseInt(index))
  $('#'+name).addClass('container')
}

View.prototype.del_window = function(win) {
  $('#content').tabs('remove', win)
}

View.prototype.set_window_activity = function(win, level) {
  /* data_level - 0=no new data, 1=text, 2=msg, 3=highlighted text */
  win = parseInt(win)
  if(win != this.current_window()) {
    var idx = win + 1
    var li = $('#content ul li:nth-child('+idx+') span')
    var cur = parseInt(li.text().replace(/[*!+]/, ''))
    
    if(cur == win){
      switch(level) {
        case 0:
          li.text(cur)
          break;
        case 1:
          li.text(cur+'+')
          break;
        case 2:
          li.text(cur+'*')
          break;
        case 3:
          li.text(cur+'!')
          break;
      }
    }
  }
}

View.prototype.current_window = function() {
  return $('#content').tabs('option', 'selected')
}

View.prototype.set_content = function(win, html) {
  $('#'+win).html(html)
  $('#'+win).append('<br/>')
}

View.prototype.append_message = function(win, msg) {
  var t = $('#'+win)
  $(t).append(msg+'<br/>')
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
  this.append_message('server', time.join(':') + ' ==> ' + msg)
}

View.prototype.sort_windows = function(event, ui) {
  $('#content li').sort(function(a, b){
    var ai = parseInt($(a).text().replace(/[*!+]/, ''))
    var bi = parseInt($(b).text().replace(/[*!+]/, ''))
    
    if(ai > bi) {
      return 1;
    } else {
      return -1;
    }
  }).appendTo('#content ul')
}