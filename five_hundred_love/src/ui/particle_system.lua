local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

function ParticleSystem.new()
    local self = setmetatable({}, ParticleSystem)
    self.particles = {}
    return self
end

function ParticleSystem:emit(params)
    local count = params.count or 10
    local x = params.x or 0
    local y = params.y or 0
    local color = params.color or {1, 1, 1}
    local speed = params.speed or 100
    local spread = params.spread or math.pi * 2
    local life = params.life or 1.0
    
    for i = 1, count do
        local angle = (params.angle or 0) + (love.math.random() - 0.5) * spread
        local vel = love.math.random(speed * 0.5, speed * 1.5)
        
        table.insert(self.particles, {
            x = x,
            y = y,
            vx = math.cos(angle) * vel,
            vy = math.sin(angle) * vel,
            life = life * love.math.random(0.8, 1.2),
            max_life = life,
            color = color,
            size = love.math.random(2, 5),
            gravity = params.gravity or 200
        })
    end
end

function ParticleSystem:update(dt)
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.life = p.life - dt
        
        if p.life <= 0 then
            table.remove(self.particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy + p.gravity * dt -- Gravity
            p.vx = p.vx * 0.95 -- Air drag
        end
    end
end

function ParticleSystem:draw()
    for _, p in ipairs(self.particles) do
        local alpha = p.life / p.max_life
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
        love.graphics.rectangle("fill", p.x, p.y, p.size, p.size)
    end
end

return ParticleSystem
