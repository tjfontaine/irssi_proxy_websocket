var EventEmitter;
var sys;
var util;

/*if(require) {
  EventEmitter = require('events').EventEmitter
  sys = require('sys')
  util = require('util')
}*/

function splitMax(str, sep, max) {
  var tmp = str.split(sep, max)
  var txt = tmp.join(sep)
  var rest = str.replace(txt, '').replace(sep, '')
  tmp.push(rest)
  return tmp
}

var IRCParser = function(socket) {
  var self = this
  var leftOver = ''
  
  self.parsePacket = function(data, userData) {
    leftOver += data
    var messages = leftOver.split(/\n/)
    for(i in messages) {
      var message = messages[i]
      var omessage = message
      
      if(message.substr(-1) == '\r') {
        message = message.replace('\r', '')

        var source = null
        var parts = null
        
        if(message[0] == ':') {
          parts = splitMax(message, ' ', 1)
          source = parts[0].substr(1)
          message = parts[1]
        }
        
        parts = splitMax(message, ' ', 1)

        var command = '';
        
        if(parts.length == 1) {
          command = parts[0]
          message = undefined
        } else {
          command = parts[0]
          message = parts[1]
        }
        
        var params = []
        
        while(message && message[0] != ':') {
          var middle = splitMax(message, ' ', 1)
          params.push(middle[0])
          if(middle.length > 1) {
            message = middle[1]
          } else {
            message = null
          }
        }
        
        if(message && message[0] == ':') {
          params.push(message.substr(1))
        }
       
        var rawcommand = command.toUpperCase()
        command = 'cmd_' + command.toUpperCase()
        //console.log(command, source, params)

        if(self[command]) {
          self[command].apply(self, [source].concat(params))
        } else if(self.unhandled) {
          self.unhandled(rawcommand, [source, params], userData)
        }
      } else {
        leftOver = message
        break
      }
    }

    if(socket.on) {
      socket.on('data', self.parsePacket)
    }
  }
  Object.defineProperty(this, 'socket', { get: function() { return socket; }, enumerable: true})
}

if(EventEmitter) {
  sys.inherits(IRC, EventEmitter)
}

IRCParser.prototype.write = function(data) {
  if(this.socket.write) {
    this.socket.write(data)
  } else {
    this.socket.send(data)
  }
}

IRCParser.prototype.sendMessage = function(message) {
  //console.log('sending ...' + message)
  this.write(message+"\r\n")
}

IRCParser.prototype.nick = function(newnick) {
  this.sendMessage('NICK '+newnick)
}

IRCParser.prototype.user = function(username, hostname, servername, realname) {
  this.sendMessage('USER ' + [username, hostname, servername].join(' ') + ' :' + realname)
}

IRCParser.prototype.pass = function(pass) {
  this.sendMessage('PASS ' + pass)
}

IRCParser.prototype.pong = function(cookie) {
  this.sendMessage('PONG '+cookie)
}

IRCParser.prototype.server = function(servname, hopcount, info) {
  this.sendMessage('SERVER ' + [servname, hopcount.toString()].join(' ') + ' :' + info)
}

IRCParser.prototype.oper = function(user, password) {
  this.sendMessage(['OPER', user, password].join(' '))
}

IRCParser.prototype.quit = function(message) {
  this.sendMessage('QUIT :' + message)
}

IRCParser.prototype.squit = function(server, comment) {
  this.sendMessage('SQUIT ' + server + ' :' + comment)
}

IRCParser.prototype.join = function(channels, keys) {
  if(channels instanceof String || typeof channels == "string") {
    channels = [channels]
  }
  
  if(keys instanceof String || typeof keys == "string") {
    keys = [keys]
  }
  
  this.sendMessage('JOIN ' + channels.join(',') + ' ' + keys.join(','))
}
