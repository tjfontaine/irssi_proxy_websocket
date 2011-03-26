var View = function() {
  
}

View.prototype.add_window = function(name, index) {
  $('#content').tabs('add', '#'+name, name, parseInt(index))
  $('#'+name).addClass('container')
}

View.prototype.del_window = function(win) {
  /* TODO XXX FIXME this needs to lookup by name until we sort right */
  $('#content').tabs('remove', win)
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



function sort_tabs() {
}