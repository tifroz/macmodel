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



	# 																										CONSTRUCTOR
	#
	# @param doc			the data object that should be wrapped by the MongoDoc instance 
	# @param fn				(optional) callback function with (err, MongoDoc) signature, returns after the MongoDoc was instantiated.
	# 									The object wont' be saved to storage unless the callback is passed as argument
account = new Account doc, (err, doc)->
	if doc
		console.log "OK created and saved"



	# 		FETCH to fetch all matches: Account.fetch(query, options, fn)
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		(optional) mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDocs<Array>) signature
	#
	# @return a mongodb stream that can be iterated over
Account.fetch(query, options, fn)


	#			FETCHONE to fetch the first match: Account.fetchOne(query, options, fn)
	# 
	# @see http://mongodb.github.io/node-mongodb-native/api-generated/collection.html#find
	#
	# @param query			mongodb query object e.g {color: 'blue'}, see 
	# @param options		mongodb options object e.g. {fields: {color: true}}
	# @param fn					callback with (error, MongoDoc) signature
	#
	# @return N/A
Account.fetchOne(query, options, fn)

	##########################################################################################################
	#																											Instance APIs
	##########################################################################################################

	# 

# Supplements known data with data from the storage (this assumes a matching object exists in the storage)
account = new Account(_id: '123')
account.fillFromStorage, (err, doc)->
	if err
		console.error "No matching object found?"
	else
		account.getData() # This should yield not just the _id but also all the data we could fetch from the storage 

# Save current data object to mongodb
account.save(fn)

# Attach a new set of data and save
account.setData(data, fn)

# Extends current data object (does not save)
account.extend(data)

# Update data in storage
account.update(modifier, options, fn)

# Remove from storage
account.remove()

# Get a copy of the data object attached to the instance
account.data()


```
