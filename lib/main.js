(function() {
  var MongoDoc, Seq, ThruStream, db, deepClone, events, formatQuery, logger, util, _,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    __slice = [].slice;

  events = require('events');

  _ = require('underscore');

  util = require('util');

  logger = console;

  db = require('macmongo');

  Seq = require('seq');

  ThruStream = require('stream').ThruStream;

  deepClone = function(item) {
    var i, result, types;
    if (!item) {
      return item;
    }
    types = [Number, String, Boolean];
    result = void 0;
    types.forEach(function(type) {
      if (item instanceof type) {
        return result = type(item);
      }
    });
    if (typeof result === "undefined") {
      if (Object.prototype.toString.call(item) === "[object Array]") {
        result = [];
        item.forEach(function(child, index, array) {
          return result[index] = clone(child);
        });
      } else if (typeof item === "object") {
        if (item.nodeType && typeof item.cloneNode === "function") {
          result = item.cloneNode(true);
        } else if (item.getTime) {
          result = new Date(item);
        } else if (!item.prototype) {
          result = {};
          for (i in item) {
            result[i] = clone(item[i]);
          }
        } else {
          if (false && item.constructor) {
            result = new item.constructor();
          } else {
            result = item;
          }
        }
      } else {
        result = item;
      }
    }
    return result;
  };

  formatQuery = function(query) {
    if (_.isString(query)) {
      query = {
        _id: query
      };
    }
    return query;
  };

  MongoDoc = (function(_super) {
    var collections;

    __extends(MongoDoc, _super);

    collections = {};

    MongoDoc._tag = function() {
      return "MONGODOC (" + (this.resolveCollection().collectionName) + ")";
    };

    MongoDoc.register = function(concrete) {
      return collections[concrete.collectionName] = concrete;
    };

    MongoDoc.jsonDeserialize = function(record) {
      return record;
    };

    MongoDoc.jsonDeserializeForCollection = function(collectionName, record) {
      var concrete;
      concrete = this.concreteClass(collectionName);
      return concrete.jsonDeserialize(record);
    };

    MongoDoc.concreteClass = function(collectionName) {
      var concrete;
      concrete = collections[collectionName];
      if (!concrete) {
        logger.warning("Could not find concrete MongoDoc instance for '" + collectionName + "'. Make sure it was registered first?");
      }
      return concrete;
    };

    MongoDoc.instanceForCollection = function(collectionName, doc, options, fn) {
      var concrete;
      concrete = this.concreteClass(collectionName);
      return new concrete(doc, options, fn);
    };

    MongoDoc.fetchForCollection = function(collectionName, query, options, fn) {
      var concrete;
      concrete = this.concreteClass(collectionName);
      return concrete.fetch.apply(concrete, _.compact([query, options, fn]));
    };

    MongoDoc.fetchOneForCollection = function(collectionName, query, options, fn) {
      var concrete;
      concrete = this.concreteClass(collectionName);
      return concrete.fetchOne.apply(concrete, _.compact([query, options, fn]));
    };

    MongoDoc.resolveCollection = function() {
      if (!this.collection) {
        this.collection = db[this.collectionName];
      }
      return this.collection;
    };

    MongoDoc.remove = function() {
      var arg, args, fn, options, query, _i, _len;
      query = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      for (_i = 0, _len = args.length; _i < _len; _i++) {
        arg = args[_i];
        if (_.isFunction(arg)) {
          fn = arg;
        } else {
          options = arg;
        }
      }
      return this.resolveCollection().remove(formatQuery(query), options, fn);
    };

    MongoDoc.fetch = function(query, options, fn) {
      var args, batch, boo, stream;
      args = _.toArray(arguments);
      query = args.shift();
      fn = args.pop();
      options = args.shift() || {};
      try {
        stream = this.resolveCollection().find(formatQuery(query), options).stream();
        if (_.isFunction(fn)) {
          batch = [];
          stream.on('data', (function(_this) {
            return function(data) {
              return batch.push(new _this(data, {
                save: false
              }));
            };
          })(this));
          stream.on('end', function() {
            return fn(null, batch);
          });
          stream.on('error', function(err) {
            return fn(err);
          });
        }
        return stream;
      } catch (_error) {
        boo = _error;
        logger.error(boo);
        return fn(boo);
      }
    };

    MongoDoc.fetchOne = function(query, options, fn) {
      var args, self;
      args = _.toArray(arguments);
      query = args.shift();
      fn = args.pop();
      options = args.shift() || {};
      self = this;
      return Seq().seq(function() {
        return self.resolveCollection().findOne(formatQuery(query), options, this);
      }).seq(function(doc) {
        if (!doc) {
          logger.warning(util.format("" + (self._tag()) + " query %j matched no records in collection %s", query, self.collection.collectionName));
          return fn();
        } else {
          return new self(doc, {
            save: false
          }, fn);
        }
      })["catch"](function(boo) {
        logger.error(boo);
        return fn(boo);
      });
    };

    function MongoDoc() {
      var arg, args, doc, fn, options, self, _i, _len;
      doc = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      this.remove = __bind(this.remove, this);
      this.update = __bind(this.update, this);
      this.onUpdate = __bind(this.onUpdate, this);
      this.setData = __bind(this.setData, this);
      this.save = __bind(this.save, this);
      for (_i = 0, _len = args.length; _i < _len; _i++) {
        arg = args[_i];
        if (_.isFunction(arg)) {
          fn = arg;
        } else {
          options = arg;
        }
      }
      this._modifier = {};
      this._beforeData = {};
      if (doc) {
        this._data = doc;
        if ((options != null ? options.save : void 0) === true) {
          self = this;
          Seq().seq(function() {
            return self.save(this);
          }).seq(function() {
            self.init();
            return typeof fn === "function" ? fn(null, self) : void 0;
          })["catch"](function(boo) {
            logger.error(boo);
            return typeof fn === "function" ? fn(boo) : void 0;
          });
        } else {
          this.init();
          if (typeof fn === "function") {
            fn(null, this);
          }
        }
      }
    }

    MongoDoc.prototype.init = function() {};

    MongoDoc.prototype.data = function() {
      return deepClone(this._data);
    };

    MongoDoc.prototype.save = function(fn) {
      var collection, notify;
      collection = this.constructor.resolveCollection();
      if (this.constructor.timelineEnabled) {
        this._data.timeline = {
          created: new Date(),
          updated: new Date()
        };
      }
      notify = (function(_this) {
        return function() {
          if (_.isFunction(_this.constructor.onInsert)) {
            return process.nextTick(function() {
              return _this.constructor.onInsert(_this.data());
            });
          }
        };
      })(this);
      if (this._data._id) {
        collection.update({
          _id: this._data._id
        }, this._data, {
          upsert: true
        }, (function(_this) {
          return function(err, res) {
            return collection.findOne({
              _id: _this._data._id
            }, function(err, doc) {
              _this._data = doc;
              notify();
              return typeof fn === "function" ? fn(err, _this) : void 0;
            });
          };
        })(this));
      } else {
        this._data._id = db.uid();
        collection.insert(this._data, (function(_this) {
          return function(err, res) {
            _this._data = res[0];
            notify();
            return typeof fn === "function" ? fn(err, _this) : void 0;
          };
        })(this));
      }
      return this;
    };

    MongoDoc.prototype.setData = function(data, fn) {
      var before, self;
      before = this._data;
      self = this;
      return Seq().seq(function() {
        return self.constructor.resolveCollection().save(data, this);
      }).seq(function() {
        self._data = data;
        self.onUpdate(before);
        return typeof fn === "function" ? fn(null, self) : void 0;
      })["catch"](function(boo) {
        return typeof fn === "function" ? fn(boo) : void 0;
      });
    };

    MongoDoc.prototype.jsonSerialize = function(doc) {
      return doc;
    };

    MongoDoc.prototype.onUpdate = function(beforeData) {
      if (_.isFunction(this.constructor.onUpdate)) {
        return process.nextTick((function(_this) {
          return function() {
            return _this.constructor.onUpdate(beforeData, _this.data());
          };
        })(this));
      }
    };

    MongoDoc.prototype.update = function(modifier, options, fn) {
      var $setModifier, args, before, err, id, modif, self;
      args = _.toArray(arguments);
      if (args.length < 3) {
        fn = options;
        options = null;
      }
      if (_.size(this._modifier) === 0) {
        this._beforeData = this._data;
      }
      _.extend(this._modifier, modifier);
      if ((options != null ? options.save : void 0) !== false) {
        if (id = this._data._id) {
          self = this;
          if (this.constructor.timelineEnabled) {
            $setModifier = this._modifier["$set"] || {};
            $setModifier["timeline.updated"] = new Date();
            this._modifier["$set"] = $setModifier;
          }
          modif = this._modifier;
          before = this._beforeData;
          this._modifier = {};
          this._beforeData = {};
          this.constructor.resolveCollection().findAndModify({
            _id: id
          }, [["_id", 1]], modif, {
            'new': true
          }, (function(_this) {
            return function(err, res) {
              if (err) {
                logger.error(util.format("ERROR Failed to 'findAndModify' " + (self.constructor._tag()) + " with modifier %j, selector (%j)", modif, {
                  _id: id
                }));
                logger.error(err);
              } else {
                _this._data = res;
                if (_.isFunction(_this.constructor.onUpdate)) {
                  process.nextTick(function() {
                    return _this.constructor.onUpdate(before, _this.data());
                  });
                }
              }
              return typeof fn === "function" ? fn(err, _this) : void 0;
            };
          })(this));
        } else {
          err = new Error("" + (self.constructor._tag()) + " Can't update a record not already in the db");
          if (typeof fn === "function") {
            fn(err);
          }
          throw err;
        }
      }
      return this;
    };

    MongoDoc.prototype.remove = function(fn) {
      if (fn == null) {
        fn = (function() {});
      }
      if (this._data._id) {
        return this.constructor.resolveCollection().remove({
          _id: this._data._id
        }, fn);
      } else {
        return fn(null, 0);
      }
    };

    return MongoDoc;

  })(events.EventEmitter);

  _.extend(MongoDoc, events.EventEmitter);

  module.exports = MongoDoc;

}).call(this);