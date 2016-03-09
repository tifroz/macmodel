# macmodel
model generation helpers for macmongo


## installation

```js
npm install macmodel
```

# usage

```coffeescript
MongoDoc					= require 'macmodel'
events						= require 'events'
Seq 							= require 'seq'

# Account is a fictional model object used to illustrate. MongoDoc is essentially an abstract object that is only useful when subclasses

class Account extends MongoDoc

Account.init = ->
	console.log @data()

Account.nameHasValidationError = (username)->
	if username.length < 2 or not username
		return "Username must be 2+ characters"
	return false
Account.passwordHasValidationError = (password)->
	if password.length < 3 or not password
		return "Password must be 3+ characters"
	return false
Account.createAccount = (accountData, fn)->
	if errorText = Account.nameHasValidationError(accountData.username)
		return fn(new Error(errorText))
	else if errorText = Account.passwordHasValidationError(accountData.password)
		return fn(new Error(errorText))
	else
		Seq().seq ->
			Account.fetchOne {username: accountData.username}, this
		.seq (account)->
			if account
				this(new Error("Username already exists"))
			else
				Account.fetchOne {accountId: accountData.accountId}, this
		.seq (account)->
			if account
				this(new Error("Cannot create multiple accounts from this device"))
			else
				accountData.created = new Date()
				new Account accountData, {save: true}, this
		.seq (account)->
			fn(null, account)
		.catch (error)->
			fn(error)

_.extend Account, events.EventEmitter.prototype

Account.collectionName = 'Account'
MongoDoc.register(Account)


# APIs

	########################################################################################################
	#																											Class APIs
	##########################################################################################################


	# 	CONSTRUCTOR: account = new Account(doc, fn, options)
	#
	# @param doc			the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature, returns after the MongoDoc was instantiated
	#	@param options 	(optional) use {save: true} to persist the new object to mongodb
	#
	# Note: subclass implementation can override init()




	# 		FETCH to fetch all matches: Account.fetch(query, options, fn)
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		(optional) mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDocs<Array>) signature
	#
	# @return a mongodb stream that can be iterated over



	#			FETCHONE to fetch the first match: Account.fetchOne(query, options, fn)
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDoc) signature
	#
	# @return N/A


	##########################################################################################################
	#																											Instance APIs
	##########################################################################################################

	# 
	# account.save()
	# account.setData(data, fn)
	# account.update(modifier, options, fn)
	# account.remove()


```
