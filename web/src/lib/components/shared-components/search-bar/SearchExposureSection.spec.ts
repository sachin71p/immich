import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import SearchExposureSection from '$lib/components/shared-components/search-bar/SearchExposureSection.svelte';
import { searchManager } from '$lib/managers/search-manager.svelte';

// fork: shared-libraries
describe('SearchExposureSection component', () => {
  afterEach(() => {
    searchManager.reset();
  });

  it('updates the ISO min/max filter when typed into', async () => {
    const user = userEvent.setup();
    render(SearchExposureSection);

    const inputs = screen.getAllByRole('spinbutton');
    await user.type(inputs[0], '100');
    await user.type(inputs[1], '3200');

    expect(searchManager.filter.exposure.isoMin).toBe(100);
    expect(searchManager.filter.exposure.isoMax).toBe(3200);
  });

  it('updates the f-number (aperture) min/max filter when typed into', async () => {
    const user = userEvent.setup();
    render(SearchExposureSection);

    const inputs = screen.getAllByRole('spinbutton');
    await user.type(inputs[2], '1.4');
    await user.type(inputs[3], '8');

    expect(searchManager.filter.exposure.fNumberMin).toBe(1.4);
    expect(searchManager.filter.exposure.fNumberMax).toBe(8);
  });

  it('updates the focal length min/max filter when typed into', async () => {
    const user = userEvent.setup();
    render(SearchExposureSection);

    const inputs = screen.getAllByRole('spinbutton');
    await user.type(inputs[4], '24');
    await user.type(inputs[5], '70');

    expect(searchManager.filter.exposure.focalLengthMin).toBe(24);
    expect(searchManager.filter.exposure.focalLengthMax).toBe(70);
  });

  it('clears the filter value when the input is emptied', async () => {
    const user = userEvent.setup();
    render(SearchExposureSection);

    const inputs = screen.getAllByRole('spinbutton');
    await user.type(inputs[0], '100');
    expect(searchManager.filter.exposure.isoMin).toBe(100);

    await user.clear(inputs[0]);
    expect(searchManager.filter.exposure.isoMin).toBeUndefined();
  });
});
