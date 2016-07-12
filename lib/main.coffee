events			= require 'events'
_ 					= require 'underscore'
util				= require 'util'
logger			= console
db					= require 'macmongo'
Seq					= require 'seq'


ThruStream = require('stream').ThruStream


formatQuery = (query)->
	if _.isString(query)
		query = {_id: query}
	return query

clone = (item) ->
	return item	unless item # null, undefined values check
	types = [Number, String, Boolean]
	result = undefined
	
	# normalizing primitives if someone did new String('aaa'), or new Number('444');
	types.forEach (type) ->
		result = type(item)	if item instanceof type

	if typeof result is "undefined"
		if Object::toString.call(item) is "[object Array]"
			result = []
			item.forEach (child, index, array) ->
				result[index] = clone(child)

		else if typeof item is "object"
			
			# testing that this is DOM
			if item.nodeType and typeof item.cloneNode is "function"
				result = item.cloneNode(true)
			else if item.getTime
				result = new Date(item)
			else unless item:: # check that this is a literal
				# it is an object literal
				result = {}
				for i of item
					result[i] = clone(item[i])
			else
				
				# depending what you would like here,
				# just keep the reference, or create new object
				if false and item.constructor
					
					# would not advice to do that, reason? Read below
					result = new item.constructor()
				else
					result = item
		else
			result = item
	return result


class MongoDoc extends events.EventEmitter
	collections = {}
	
	@_tag: ->
		return "MONGODOC (#{@resolveCollection().collectionName})"
	
	@db : db

	@setLogger: (l)->
		logger = l

	@register: (concrete)->
		collections[concrete.collectionName] = concrete
	@jsonDeserialize:(record)->
		return record
	@jsonDeserializeForCollection: (collectionName, record)->
		concrete = @concreteClass(collectionName)
		return concrete.jsonDeserialize(record)
	@concreteClass: (collectionName)->
		concrete = collections[collectionName]
		if not concrete
			logger.warn "Could not find concrete MongoDoc instance for '#{collectionName}'. Make sure it was registered first?"
		return concrete

	@instanceForCollection: (collectionName, doc, options, fn)->
		concrete = @concreteClass(collectionName)
		return new concrete(doc, options, fn)
	@fetchForCollection:  (collectionName, query, options, fn)->
		concrete = @concreteClass(collectionName)
		return concrete.fetch.apply(concrete, _.compact([query, options, fn]))
	@fetchOneForCollection:  (collectionName, query, options, fn)->
		concrete = @concreteClass(collectionName)
		return concrete.fetchOne.apply(concrete, _.compact([query, options, fn]))

	@resolveCollection: ->
		unless @collection
			@collection = db[@collectionName]
		return @collection	
	
	@remove: (query, args...)->			# (query[, options], callback)
		for arg in args
			if _.isFunction arg
				fn = arg
			else
				options = arg
		@resolveCollection().remove(formatQuery(query), options, fn)
	


	##########################################################################################################
	# 																									FETCH
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		(optional) mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDocs<Array>) signature
	#
	# @return a mongodb stream that can be iterated over
	##########################################################################################################
	@fetch: (query, options, fn)->
		args = _.toArray(arguments)
		query = args.shift()
		fn = args.pop()
		options = args.shift() or {}
		try
			stream = @resolveCollection().find(formatQuery(query), options).stream()
			if _.isFunction(fn)
				batch = []
				stream.on 'data', (data)=>
					batch.push( new @(data, {save: false}) )
				stream.on 'end', ->
					fn(null, batch)
				stream.on 'error', (err)->
					fn(err)
			return stream	
		catch boo
			logger.error boo
			fn boo

	##########################################################################################################
	#																											FETCHONE
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDoc) signature
	#
	# @return N/A
	##########################################################################################################
	@fetchOne: (query, options, fn)->
		args = _.toArray(arguments)
		query = args.shift()
		fn = args.pop()
		options = args.shift() or {}
		self = @
		Seq().seq ->
			self.resolveCollection().findOne formatQuery(query), options, this
		.seq (doc)->
			if not doc
				logger.warn util.format("#{self._tag()} query %j matched no records in collection %s", query, self.collection.collectionName)
				fn()
			else
				fn?(null, new self(doc))
		.catch (boo)->
			logger.error boo
			fn boo



	##########################################################################################################
	# 																										CONSTRUCTOR
	#
	# @param doc			the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature, returns after the MongoDoc was instantiated.
	# 									The object wont' be saved to storage unless the callback is passed as argument
	##########################################################################################################
	constructor: (doc, fn)->
		@_needsFillFromStorage = true
		@_modifier = {}
		@_beforeData = {}
		if doc
			@_data = doc
			if _.isFunction fn 
				self = @
				Seq().seq ->
					#logger.log util.format("Saving %j to #{self.constructor.collectionName}", self._data)
					self.save this
				.seq ->
					self.init()
					fn(null, self)
				.catch (boo)->
					logger.error boo
					fn(boo)
			else
				@init()

	init: ->
		# Implementation can override
	
	data: ->
		return clone(@_data)

	save: (fn)=>
		collection = @constructor.resolveCollection()
		if @constructor.timelineEnabled
			#logger.log util.format("Saving %j to #{@constructor.collectionName}", @_data)
			@_data.timeline = 
				created: new Date()
				updated: new Date()

		notify = =>
			if _.isFunction @constructor.onInsert
					process.nextTick =>
						@constructor.onInsert @data()
		if @_data._id
			collection.update {_id: @_data._id}, @_data, {upsert: true}, (err, res)=>
				collection.findOne {_id: @_data._id}, (err, doc)=>
					if err is null
						@_data = doc
						@_needsFillFromStorage = false
						notify()
					fn?(err, @)
		else
			@_data._id = db.uid()
			collection.insert @_data, (err, res)=>
				if err is null
					@_data = res[0]
					@_needsFillFromStorage = false
					notify()
				fn?(err, @)

		return @

	##########################################################################################################
	#
	# setData - sets the data & save
	#
	# @param {Object} data	the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature, returns after the doc was saved
	##########################################################################################################
	setData: (data, fn)=>
		before = @_data
		self = @
		Seq().seq ->
			self.constructor.resolveCollection().save data, this
		.seq ->
			self._data = data
			@_needsFillFromStorage = false
			self.onUpdate before
			#if _.isFunction self.constructor.onUpdate
			#	process.nextTick =>
			#		self.constructor.onUpdate before, self.data()
			fn?(null,self)
		.catch (boo)->
			fn?(boo)

	##########################################################################################################
	# 		
	# fillFromStorage - supplements the data attached to the object with data from storage
	#
	# @param {Object} data	the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature
	##########################################################################################################
	fillFromStorage: (fn)=>
		unless @_needsFillFromStorage
			return fn?(null, @)
		self = @
		Seq().seq ->
			self.constructor.fetchOne self._data, this
		.seq (doc)->
			if doc
				self._data = _.extend doc.data(), self._data
				@_needsFillFromStorage = false
				fn?(null, self)
			else
				fn?(new Error("object.fillFromStorage() object has no match in the storage"))
		.catch (boo)->
			fn?(boo)




	##########################################################################################################
	# 																										extend - extends the current data object
	#
	# @param {Object} data	the data object that to extend the doc with
	##########################################################################################################
	extend: (data	)=>
		_.extend @_data, data

	jsonSerialize: (doc)->
		return doc

	onUpdate: (beforeData)=>
		if _.isFunction @constructor.onUpdate
				process.nextTick =>
					@constructor.onUpdate beforeData, @data()

	# @method update - updates 
	# 
	# @param {Object} modifier, e.g. {attribute: "value"}
	# @params {Object} options, {save: false} or {save: true}, default  is {save: true} - optional
	# @param {Function} fn callback(e, result) - optional
	update: (modifier, options, fn)=>
		#Sort out optional arguments
		if options is undefined
			options = save: true
		else if _.isFunction options
			fn = options
			options = save: true

		if _.size(@_modifier) is 0
			@_beforeData = @_data
		modifier = _.extend {}, @_modifier, modifier

		unless options?.save is false
			if id = @_data._id
				self = @
				if @constructor.timelineEnabled
					$setModifier = modifier["$set"] or {}
					$setModifier["timeline.updated"] = new Date()
					modifier["$set"] = $setModifier
				logger.log util.format("#{self.constructor._tag()} update modifier: %j", modifier)

				before = @_beforeData
				@_beforeData = {}
				@constructor.resolveCollection().findAndModify {_id: id}, [["_id", 1]], modifier, {'new': true}, (err, res)=>
					if err
						logger.error util.format("ERROR Failed to 'findAndModify' #{self.constructor._tag()} with modifier %j, selector (%j)", modifier, {_id: id})
						logger.error err
					else
						@_data = res
						@_needsFillFromStorage = false
						if _.isFunction @constructor.onUpdate
							process.nextTick =>
								@constructor.onUpdate before, @data()
					fn?(err, @)
			else
				err = new Error("#{self.constructor._tag()} Can't update a record not already in the db") 
				fn?(err)
		return @

	remove: (fn=(->))=>
		if @_data._id
			@constructor.resolveCollection().remove {_id: @_data._id}, fn
		else
			fn(null, 0)


_.extend MongoDoc, events.EventEmitter

module.exports = MongoDoc

