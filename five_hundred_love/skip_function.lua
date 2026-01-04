function TableView:skip_dealing_animation()
    -- Clear all animations
    self.animations = {}
    self.pending_animations = {}
    self.dealing_in_progress = false
    self.is_animating = false
    self.animation_delay_timer = 0
end
