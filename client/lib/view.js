var View = function() {
  
}

View.prototype.find_window = function(index, return_selector) {
  index = parseInt(index);
  var found = undefined;
  var found_selector = undefined;
  jQuery('#tablist li').each(function(i, li) {
    if(!found) {
      var possible_index = jQuery(li).data('index')
      if (possible_index == index) {
        found = i
        found_selector = jQuery(li).children('a').attr('href')
      }
    }
  })

  if(return_selector) {
    return found_selector;
  } else {
    return found;
  }
}

View.prototype.add_window = function(name, index) {
  jQuery('#content').tabs('add', '#'+index, name, 0)
  jQuery('#'+index).addClass('container')
  var item = jQuery('#tablist li').get(0)
  jQuery(item).data('index', parseInt(index))
  this.sort_windows()
}

View.prototype.del_window = function(win) {
  jQuery('#content').tabs('remove', this.find_window(win))
  this.sort_windows()
}

View.prototype.set_window_activity = function(win, level) {
  /* data_level - 0=no new data, 1=text, 2=msg, 3=highlighted text */
  win = parseInt(win)
  if(win != this.current_window || level == 0) {
    var idx = this.find_window(win)
    var li = jQuery('#tablist li:eq('+idx+') span')
    var cur = parseInt(li.text().replace(/[*!+]/, ''))
    
    if(cur == win){
      cur = this.activity_name(cur, level)
      li.text(cur)
    }
  }
}

View.prototype.set_notification = function (win, line) {
  /* This is a hilight check if we can notify somewhere */
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

View.prototype.set_content = function(win, lines) {
  var win_id = this.find_window(win, true)
  for (var i in lines) {
    jQuery(win_id).append(ParseColor(lines[i])+'\n')
  }
  jQuery(win_id).addClass('container')
}

View.prototype.append_message = function(win, msg) {
  var win_id = this.find_window(win, true)
  jQuery(win_id).append(ParseColor(msg)+'\n')
  jQuery(win_id).addClass('container')
}

View.prototype.clear_window = function(win) {
  var win_id = this.find_window(win, true)
  jQuery(win_id).html('')
}

View.prototype.scroll_to_bottom = function(win) {
  var win_id = this.find_window(win, true)
  var tab = jQuery(win_id)[0]
  tab.scrollTop = tab.scrollHeight;  
}

View.prototype.log = function(msg) {
  var now = new Date()
  var time = [now.getHours(), now.getMinutes(), now.getSeconds(), now.getMilliseconds()]
  this.append_message(0, time.join(':') + ' ==> ' + msg)
}

View.prototype.sort_windows = function(event, ui) {
  var items = jQuery('#tablist li')
  for (var i = 0; i < items.length && i+1 < items.length; i++) {
    var ai = jQuery(items[i]).data('index')
    var bi = jQuery(items[i+1]).data('index')
    if (ai > bi) {
      jQuery('#content').tabs('move', i, 'right')
      this.sort_windows()
    }
  }
}
