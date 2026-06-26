/*
 * Copyright (c) 2014-2026 Bjoern Kimminich & the OWASP Juice Shop contributors.
 * SPDX-License-Identifier: MIT
 */

import Hashids from 'hashids/cjs'
import { type Request, type Response } from 'express'
import { ChallengeModel } from '../models/challenge'
import { challenges } from '../data/datacache'
import { Op } from 'sequelize'
import logger from '../lib/logger'

export function continueCode () {
  const salt = process.env.CONTINUE_CODE_SALT ?? 'this is my salt'
  const hashids = new Hashids(salt, 60, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890')
  return (req: Request, res: Response) => {
    logger.info(`Continue code export (standard) using salt: "${salt}"`)
    const ids = []
    for (const challenge of Object.values(challenges)) {
      if (challenge.solved) ids.push(challenge.id)
    }
    const continueCode = ids.length > 0 ? hashids.encode(ids) : undefined
    res.json({ continueCode })
  }
}

export function continueCodeFindIt () {
  const salt = process.env.CONTINUE_CODE_SALT_FINDIT ?? 'this is the salt for findIt challenges'
  const hashids = new Hashids(salt, 60, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890')
  return async (req: Request, res: Response) => {
    logger.info(`Continue code export (findIt) using salt: "${salt}"`)
    const ids = []
    const challenges = await ChallengeModel.findAll({ where: { codingChallengeStatus: { [Op.gte]: 1 } } })
    for (const challenge of challenges) {
      ids.push(challenge.id)
    }
    const continueCode = ids.length > 0 ? hashids.encode(ids) : undefined
    res.json({ continueCode })
  }
}

export function continueCodeFixIt () {
  const salt = process.env.CONTINUE_CODE_SALT_FIXIT ?? 'yet another salt for the fixIt challenges'
  const hashids = new Hashids(salt, 60, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890')
  return async (req: Request, res: Response) => {
    logger.info(`Continue code export (fixIt) using salt: "${salt}"`)
    const ids = []
    const challenges = await ChallengeModel.findAll({ where: { codingChallengeStatus: { [Op.gte]: 2 } } })
    for (const challenge of challenges) {
      ids.push(challenge.id)
    }
    const continueCode = ids.length > 0 ? hashids.encode(ids) : undefined
    res.json({ continueCode })
  }
}
