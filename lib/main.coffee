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


class MongoDoc extends events.EventEmitter
	collections = {}
	
	@_tag: ->
		return "MONGODOC (#{@resolveCollection().collectionName})"

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
			logger.warning "Could not find concrete MongoDoc instance for '#{collectionName}'. Make sure it was registered first?"
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
				logger.warning util.format("#{self._tag()} query %j matched no records in collection %s", query, self.collection.collectionName)
				fn()
			else
				new self(doc, {save: false}, fn)
		.catch (boo)->
			logger.error boo
			fn boo

	##########################################################################################################
	# 																										CONSTRUCTOR
	#
	# @param doc			the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature, returns after the MongoDoc was instantiated
	#	@param options 	(optional) use {save: true} to persist the new object to mongodb
	##########################################################################################################
	constructor: (doc, args...)->
		for arg in args
			if _.isFunction arg
				fn = arg
			else
				options = arg

		@_modifier = {}
		@_beforeData = {}
		if doc
			@_data = doc
			if options?.save is true 
				self = @
				Seq().seq ->
					#logger.debug util.format("Saving %j to #{self.constructor.collectionName}", self._data)
					self.save this
				.seq ->
					self.init()
					fn?(null, self)
				.catch (boo)->
					logger.error boo
					fn?(boo)
			else
				@init()
				fn?(null, @)
	init: ->
		# Implementation can override
	
	data: ->
		return deepClone(@_data)

	save: (fn)=>
		collection = @constructor.resolveCollection()
		if @constructor.timelineEnabled
			#logger.debug util.format("Saving %j to #{@constructor.collectionName}", @_data)
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
					#logger.debug util.format("Fetched %j", doc)
					@_data = doc
					notify()
					fn?(err, @)
		else
			@_data._id = db.uid()
			collection.insert @_data, (err, res)=>
				@_data = res[0]
				notify()
				fn?(err, @)

		return @

	setData: (data, fn)=>
		before = @_data
		self = @
		Seq().seq ->
			self.constructor.resolveCollection().save data, this
		.seq ->
			self._data = data
			self.onUpdate before
			#if _.isFunction self.constructor.onUpdate
			#	process.nextTick =>
			#		self.constructor.onUpdate before, self.data()
			fn?(null,self)
		.catch (boo)->
			fn?(boo)

	jsonSerialize: (doc)->
		return doc

	onUpdate: (beforeData)=>
		if _.isFunction @constructor.onUpdate
				process.nextTick =>
					@constructor.onUpdate beforeData, @data()

	update: (modifier, options, fn)=>
		#Sort out optional arguments
		args = _.toArray arguments
		if args.length < 3
			fn = options
			options = null
		if _.size(@_modifier) is 0
			@_beforeData = @_data
		_.extend @_modifier, modifier

		unless options?.save is false
			if id = @_data._id
				self = @
				if @constructor.timelineEnabled
					$setModifier = @_modifier["$set"] or {}
					$setModifier["timeline.updated"] = new Date()
					@_modifier["$set"] = $setModifier
				#logger.debug util.format("#{self.constructor._tag()} update modifier: %j", @_modifier)
				modif = @_modifier
				before = @_beforeData
				@_modifier = {}
				@_beforeData = {}
				@constructor.resolveCollection().findAndModify {_id: id}, [["_id", 1]], modif, {'new': true}, (err, res)=>
					if err
						logger.error util.format("ERROR Failed to 'findAndModify' #{self.constructor._tag()} with modifier %j, selector (%j)", modif, {_id: id})
						logger.error err
					else
						#logger.debug util.format("#{self.constructor._tag()} with id #{id} was updated as %j", res)
						@_data = res
						if _.isFunction @constructor.onUpdate
							process.nextTick =>
								@constructor.onUpdate before, @data()
					fn?(err, @)
			else
				err = new Error("#{self.constructor._tag()} Can't update a record not already in the db") 
				fn?(err)
				throw err
		return @

	remove: (fn=(->))=>
		if @_data._id
			@constructor.resolveCollection().remove {_id: @_data._id}, fn
		else
			fn(null, 0)


_.extend MongoDoc, events.EventEmitter

module.exports = MongoDoc

