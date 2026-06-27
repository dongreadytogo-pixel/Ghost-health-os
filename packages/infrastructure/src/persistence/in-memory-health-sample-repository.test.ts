import { testHealthSampleRepositoryContract } from './health-sample-repository.contract.js';
import { InMemoryHealthSampleRepository } from './in-memory-health-sample-repository.js';

testHealthSampleRepositoryContract(
  'InMemoryHealthSampleRepository',
  () => new InMemoryHealthSampleRepository(),
);
