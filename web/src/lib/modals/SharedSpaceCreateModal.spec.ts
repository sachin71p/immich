import userEvent from '@testing-library/user-event';
import { renderWithTooltips } from '$tests/helpers';
import SharedSpaceCreateModal from './SharedSpaceCreateModal.svelte';

describe('SharedSpaceCreateModal', () => {
  it('requires a shared-library name before creation is enabled', async () => {
    const { getByLabelText, getByRole } = renderWithTooltips(SharedSpaceCreateModal, { onClose: vi.fn() });
    const create = getByRole('button', { name: 'create' });
    expect(create).toBeDisabled();

    await userEvent.setup().type(getByLabelText('name'), 'Family photos');

    expect(create).toBeEnabled();
  });
});
