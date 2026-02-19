--!strict
-- Signal.luau
-- A robust Signal implementation for Roblox Luau

local Signal = {}
Signal.__index = Signal

type ConnectionImpl = {
	Disconnect: (self: ConnectionImpl) -> (),
	Connected: boolean,
	_signal: SignalInternal,
	_fn: (...any) -> (),
	_next: ConnectionImpl?,
	_prev: ConnectionImpl?,
}

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal = {
	Fire: (self: Signal, ...any) -> (),
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Destroy: (self: Signal) -> (),
}

type SignalInternal = {
	_handlerListHead: ConnectionImpl?,
	Fire: (self: SignalInternal, ...any) -> (),
	Connect: (self: SignalInternal, fn: (...any) -> ()) -> Connection,
	Wait: (self: SignalInternal) -> ...any,
	Destroy: (self: SignalInternal) -> (),
}

function Signal.new(): Signal
	local self = setmetatable({
		_handlerListHead = nil :: ConnectionImpl?,
	}, Signal)
	return (self :: any) :: Signal
end

function Signal.Connect(self: SignalInternal, fn: (...any) -> ()): Connection
	local connection: ConnectionImpl = {
		_signal = self,
		_fn = fn,
		_next = self._handlerListHead,
		_prev = nil,
		Connected = true,
		Disconnect = function(self) end,
	}
	
	function connection:Disconnect()
		if not self.Connected then return end
		self.Connected = false

		if self._prev then
			self._prev._next = self._next
		else
			self._signal._handlerListHead = self._next
		end

		if self._next then
			self._next._prev = self._prev
		end
	end

	if self._handlerListHead then
		self._handlerListHead._prev = connection
	end
	self._handlerListHead = connection

	return connection
end

function Signal.Fire(self: SignalInternal, ...: any)
	local item = self._handlerListHead
	while item do
		if item.Connected then
			task.spawn(item._fn, ...)
		end
		item = item._next
	end
end

function Signal.Wait(self: SignalInternal): ...any
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Destroy(self: SignalInternal)
	self._handlerListHead = nil
end

return Signal
