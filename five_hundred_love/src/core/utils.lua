local Utils = {}

function Utils.class(name)
    local Class = {}
    Class.__index = Class
    Class.__name = name
    
    function Class.new(...)
        local self = setmetatable({}, Class)
        if self.init then self:init(...) end
        return self
    end
    
    return Class
end

return Utils
