// Short, interruptible transitions. Data operations never wait for an animation.
export class UiMotion {
  static readonly press: number = 120
  static readonly section: number = 180
  static readonly pageDuration: number = 210

  static page(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: UiMotion.pageDuration, curve: Curve.EaseOut }),
      TransitionEffect.opacity(0).animation({ duration: 90, curve: Curve.EaseOut }))
  }

  static reveal(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.opacity(0).combine(TransitionEffect.translate({ y: 5 }))
        .animation({ duration: UiMotion.section, curve: Curve.EaseOut }),
      TransitionEffect.opacity(0).animation({ duration: UiMotion.press, curve: Curve.EaseOut }))
  }

  static fade(): TransitionEffect {
    return TransitionEffect.opacity(0).animation({ duration: UiMotion.press, curve: Curve.EaseOut })
  }
}
